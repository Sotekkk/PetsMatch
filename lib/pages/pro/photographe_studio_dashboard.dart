// Accueil photographe : tableau de bord du studio. Données réelles et modules
// EXISTANTS : agenda (rdv), catalogue (prestations_photographe), galeries
// (albums_photo + statut, migration_photographe_galeries_statut.sql), devis,
// contrats (documents_animaux type contrat_prestation_photo). Les
// statistiques (CA, avis, zone) restent sur PhotographeDashboardPage.
// Miroir site : website/src/components/dashboard/PhotographeDashboard.tsx.
// Scopé au profil actif (pro_profile_id).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/utils/messaging_helper.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/pro/education_devis_page.dart' show DevisPage, DevisPrefill;
import 'package:PetsMatch/pages/pro/photographe_contrats_page.dart';
import 'package:PetsMatch/pages/pro/photographe_album_page.dart';
import 'package:PetsMatch/pages/pro/photographe_galeries_page.dart';
import 'package:PetsMatch/pages/pro/photographe_dashboard_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart' show FacturationPage, CreerFacturePage, FacturePrefillLigne;
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';

const _teal = kDashTeal;
const _ink = kDashInk;
const _muted = kDashMuted;
const _vert = Color(0xFF2E7D5E);
const _ambre = Color(0xFFD97706);
const _violet = Color(0xFF7B5EA7);

/// Statuts de galerie (miroir site lib/photographe.ts).
({String label, Color fg, Color bg}) styleGalerie(String? s) => switch (s) {
      'partagee' => (label: 'En attente de sélection', fg: const Color(0xFF1D4ED8), bg: const Color(0xFFE8F0FE)),
      'selection_recue' => (label: 'Sélection reçue', fg: _ambre, bg: const Color(0xFFFFF4DC)),
      'en_retouche' => (label: 'En retouche', fg: _violet, bg: const Color(0xFFF1ECF8)),
      'livree' => (label: 'Livrée', fg: _vert, bg: const Color(0xFFE7F3EC)),
      'archivee' => (label: 'Archivée', fg: const Color(0xFF6B7280), bg: const Color(0xFFF3F4F6)),
      _ => (label: 'Brouillon', fg: const Color(0xFF4B5563), bg: const Color(0xFFF1F2F4)),
    };
const kGaleriesALivrer = {'brouillon', 'partagee', 'selection_recue', 'en_retouche'};

class PhotographeStudioDashboard extends StatefulWidget {
  const PhotographeStudioDashboard({super.key});

  @override
  State<PhotographeStudioDashboard> createState() => _PhotographeStudioDashboardState();
}

class _PhotographeStudioDashboardState extends State<PhotographeStudioDashboard> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  bool _statutDispo = true;
  List<Map<String, dynamic>> _seances = [];
  List<Map<String, dynamic>> _passees = [];
  List<Map<String, dynamic>> _demandes = [];
  List<Map<String, dynamic>> _galeries = [];
  List<Map<String, dynamic>> _devis = [];
  List<Map<String, dynamic>> _contratsAttente = [];
  // Dossier de chaque séance : devis (devis.rdv_id), contrats (tous
  // statuts), factures (factures.source_rdv_id), prix du catalogue.
  List<Map<String, dynamic>> _devisSeances = [];
  List<Map<String, dynamic>> _contratsSeances = [];
  List<Map<String, dynamic>> _facturesSeances = [];
  final Map<String, double> _prixPrestations = {};
  final Map<String, int> _nbPhotos = {};
  final Map<String, String> _clients = {};
  final Map<String, String> _animaux = {};
  final Map<String, String> _prestations = {};
  final _galeriesKey = GlobalKey();

  String get _pid {
    final p = User_Info.activeProfileId;
    if (p.isNotEmpty) return p;
    for (final x in User_Info.availableProfiles) {
      if (x['is_main'] == true) return x['id']?.toString() ?? '';
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _charger();
  }

  List<Map<String, dynamic>> _l(dynamic r) =>
      List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map)));

  Future<void> _charger() async {
    final pid = _pid;
    if (pid.isEmpty) { setState(() => _loading = false); return; }
    final now = DateTime.now();
    try {
      _seances = _l(await _supa.from('rdv').select().eq('pro_profile_id', pid).eq('statut', 'confirme')
          .gte('date_heure', now.subtract(const Duration(hours: 6)).toUtc().toIso8601String())
          .lt('date_heure', now.add(const Duration(days: 30)).toUtc().toIso8601String())
          .order('date_heure').limit(40));
    } catch (_) {}
    try {
      // Séances des 60 derniers jours : galerie à créer si aucune n'existe.
      _passees = _l(await _supa.from('rdv').select().eq('pro_profile_id', pid).inFilter('statut', ['confirme', 'termine'])
          .gte('date_heure', now.subtract(const Duration(days: 60)).toUtc().toIso8601String())
          .lt('date_heure', now.toUtc().toIso8601String()).order('date_heure', ascending: false));
    } catch (_) {}
    try {
      _demandes = _l(await _supa.from('rdv').select().eq('pro_profile_id', pid)
          .inFilter('statut', ['demande', 'contre_proposition']).order('date_heure'));
    } catch (_) {}
    try {
      _galeries = _l(await _supa.from('albums_photo').select().eq('pro_profile_id', pid)
          .order('updated_at', ascending: false).limit(60));
      _statutDispo = true;
    } catch (_) {
      // Migration des statuts pas encore passée : liste sans statut.
      _statutDispo = false;
      try {
        _galeries = _l(await _supa.from('albums_photo').select().eq('pro_profile_id', pid)
            .order('created_at', ascending: false).limit(60));
      } catch (_) { _galeries = []; }
    }
    try {
      _devis = _l(await _supa.from('devis').select('id, numero_devis, date_devis, total_ttc, client_profile_id, nom_client, prenom_client, statut')
          .eq('pro_profile_id', pid).eq('statut', 'envoye').order('date_devis', ascending: false));
    } catch (_) {}
    try {
      _contratsAttente = _l(await _supa.from('documents_animaux').select('id, rdv_id, titre, created_at')
          .eq('pro_profile_id', pid).eq('type', 'contrat_prestation_photo').eq('statut', 'en_attente'));
    } catch (_) {}
    final rdvIds = {for (final r in [..._seances, ..._passees]) r['id'].toString()}.toList();
    if (rdvIds.isNotEmpty) {
      try {
        _devisSeances = _l(await _supa.from('devis').select('id, rdv_id, statut, total_ttc, numero_devis').inFilter('rdv_id', rdvIds));
      } catch (_) { _devisSeances = []; }
      try {
        _contratsSeances = _l(await _supa.from('documents_animaux').select('id, rdv_id, statut')
            .eq('type', 'contrat_prestation_photo').inFilter('rdv_id', rdvIds));
      } catch (_) {}
      try {
        _facturesSeances = _l(await _supa.from('factures').select('id, source_rdv_id, statut, total_ttc').inFilter('source_rdv_id', rdvIds));
      } catch (_) {}
    }
    final ids = _galeries.map((g) => g['id'].toString()).toList();
    _nbPhotos.clear();
    if (ids.isNotEmpty) {
      try {
        for (final p in await _supa.from('album_photos').select('album_id').inFilter('album_id', ids)) {
          final k = p['album_id'].toString();
          _nbPhotos[k] = (_nbPhotos[k] ?? 0) + 1;
        }
      } catch (_) {}
    }
    final tous = [..._seances, ..._passees, ..._demandes];
    final profils = {
      for (final r in [...tous, ..._galeries, ..._devis]) if (r['client_profile_id'] != null) r['client_profile_id'].toString(),
    };
    final animaux = {for (final r in tous) if (r['animal_id'] != null) r['animal_id'].toString()};
    final prestas = {for (final r in tous) if (r['prestation_id'] != null) r['prestation_id'].toString()};
    try {
      if (profils.isNotEmpty) {
        for (final p in await _supa.from('user_profiles_complet').select('id, firstname, lastname, nom, profile_type').inFilter('id', profils.toList())) {
          final perso = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
          final st = (p['nom']?.toString() ?? '').trim();
          _clients[p['id'].toString()] = p['profile_type'] != 'particulier' && st.isNotEmpty ? st : (perso.isNotEmpty ? perso : st);
        }
      }
    } catch (_) {}
    try {
      if (animaux.isNotEmpty) {
        for (final a in await _supa.from('animaux').select('id, nom').inFilter('id', animaux.toList())) {
          _animaux[a['id'].toString()] = a['nom']?.toString() ?? '';
        }
      }
    } catch (_) {}
    try {
      if (prestas.isNotEmpty) {
        for (final p in await _supa.from('prestations_photographe').select('id, nom, prix').inFilter('id', prestas.toList())) {
          _prestations[p['id'].toString()] = p['nom']?.toString() ?? '';
          _prixPrestations[p['id'].toString()] = (p['prix'] as num?)?.toDouble() ?? 0;
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  DateTime _debut(Map<String, dynamic> r) => DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal() ?? DateTime(2000);
  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _jour(DateTime d) {
    const j = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
    const m = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
    return '${j[d.weekday - 1]} ${d.day} ${m[d.month - 1]}';
  }
  String _nomClient(Map<String, dynamic> r) {
    final n = _clients[r['client_profile_id']?.toString() ?? ''];
    if (n != null && n.isNotEmpty) return n;
    final m = (r['client_nom_manuel'] ?? '${r['prenom_client'] ?? ''} ${r['nom_client'] ?? ''}').toString().trim();
    return m.isNotEmpty ? m : 'Client';
  }
  String _prestation(Map<String, dynamic> r) =>
      _prestations[r['prestation_id']?.toString()] ?? ((r['motif']?.toString() ?? '').trim().isEmpty ? 'Séance photo' : r['motif'].toString().trim());
  String? _animal(Map<String, dynamic> r) {
    final n = _animaux[r['animal_id']?.toString()] ?? r['animal_nom_manuel']?.toString();
    return n == null || n.trim().isEmpty ? null : n.trim();
  }
  Map<String, dynamic>? _galerieDe(Map<String, dynamic> r) =>
      _galeries.where((g) => g['rdv_id']?.toString() == r['id']?.toString()).firstOrNull;
  bool _contratEnAttente(Map<String, dynamic> r) =>
      _contratsAttente.any((c) => c['rdv_id']?.toString() == r['id']?.toString());
  String _statut(Map<String, dynamic> g) => _statutDispo ? (g['statut']?.toString() ?? 'brouillon') : 'brouillon';

  Future<void> _go(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _charger();
  }

  Future<void> _message(Map<String, dynamic> r) async {
    final uid = r['client_uid']?.toString();
    if (uid == null || uid.isEmpty) return;
    final conv = await MessagingHelper.openOrCreateConversation(otherUid: uid, categorie: 'services',
        myProfileId: _pid.isNotEmpty ? _pid : null);
    if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversationId: conv, eleveurId: uid)));
  }

  Future<void> _naviguer(String lieu) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(lieu)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _ouvrirGalerie(Map<String, dynamic> r) =>
      _go(PhotographeAlbumPage(rdvId: r['id'].toString(), clientName: _nomClient(r)));

  // ── Dossier de la séance (devis · contrat · galerie · facture) ─────────

  ({String texte, Color c}) _etatDevis(Map<String, dynamic> r) {
    final d = _devisSeances.where((x) => x['rdv_id']?.toString() == r['id']?.toString()).firstOrNull;
    if (d == null) return (texte: 'Aucun', c: _muted);
    final t = '${((d['total_ttc'] as num?) ?? 0).toStringAsFixed(0)} €';
    return switch (d['statut']) {
      'accepte' => (texte: 'Accepté · $t', c: _vert),
      'envoye' => (texte: 'Envoyé, en attente · $t', c: _ambre),
      'refuse' => (texte: 'Refusé', c: const Color(0xFFB3261E)),
      _ => (texte: 'Brouillon · $t', c: _muted),
    };
  }
  ({String texte, Color c}) _etatContrat(Map<String, dynamic> r) {
    final c = _contratsSeances.where((x) => x['rdv_id']?.toString() == r['id']?.toString()).firstOrNull;
    if (c == null) return (texte: 'Non généré', c: _muted);
    return switch (c['statut']) {
      'signe' => (texte: 'Signé', c: _vert),
      'partiellement_signe' => (texte: 'Signé par une partie', c: _ambre),
      'refuse' => (texte: 'Refusé', c: const Color(0xFFB3261E)),
      _ => (texte: 'En attente de signature', c: _ambre),
    };
  }
  ({String texte, Color c}) _etatGalerie(Map<String, dynamic> r) {
    final g = _galerieDe(r);
    if (g == null) return (texte: 'Pas encore créée', c: _muted);
    final st = styleGalerie(_statut(g));
    return (texte: st.label, c: st.fg);
  }
  ({String texte, Color c}) _etatFacture(Map<String, dynamic> r) {
    final f = _facturesSeances.where((x) => x['source_rdv_id']?.toString() == r['id']?.toString()
        && x['statut'] != 'annulee').firstOrNull;
    if (f == null) return (texte: 'Non facturée', c: _muted);
    final t = '${((f['total_ttc'] as num?) ?? 0).toStringAsFixed(0)} €';
    return f['statut'] == 'payee' ? (texte: 'Payée · $t', c: _vert) : (texte: 'Émise, non payée · $t', c: _ambre);
  }

  void _nouveauDevis(Map<String, dynamic> r) {
    final prix = _prixPrestations[r['prestation_id']?.toString()];
    _go(DevisPage(prefill: DevisPrefill(
      rdvId: r['id'].toString(),
      clientUid: r['client_uid']?.toString(),
      clientProfileId: r['client_profile_id']?.toString(),
      clientNom: _nomClient(r),
      animalId: r['animal_id']?.toString(),
      lignes: [if (prix != null) {'description': _prestation(r), 'quantite': 1, 'prix_unitaire': prix}],
    )));
  }

  void _facturer(Map<String, dynamic> r) {
    final prix = _prixPrestations[r['prestation_id']?.toString()] ?? 0;
    _go(CreerFacturePage(
      clientNom: _nomClient(r),
      lignesPrefill: [FacturePrefillLigne(designation: '${_prestation(r)} — séance du ${_jour(_debut(r))}', prixHT: prix, quantite: 1, tauxTVA: 20)],
      sourceRdvId: r['id'].toString(),
      sourceAnimalId: r['animal_id']?.toString(),
      clientUid: r['client_uid']?.toString(),
      clientProfileId: r['client_profile_id']?.toString(),
    ));
  }

  Future<void> _actions(Map<String, dynamic> r) async {
    final lieu = (r['lieu']?.toString() ?? '').trim();
    final galerie = _galerieDe(r);
    final animal = _animal(r);
    final notes = (r['notes_client']?.toString() ?? '').trim();
    Widget action(BuildContext ctx, IconData ic, String t, VoidCallback f) => ListTile(
          contentPadding: EdgeInsets.zero, dense: true,
          leading: Icon(ic, color: _teal),
          title: Text(t, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
          onTap: () { Navigator.pop(ctx); f(); },
        );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_prestation(r), style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
          const SizedBox(height: 2),
          Text('${_nomClient(r)} · ${_jour(_debut(r))} à ${_hm(_debut(r))} · ${(r['duree_minutes'] as num?)?.toInt() ?? 60} min',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)),
          if (lieu.isNotEmpty) Text('Lieu : $lieu', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _ink)),
          if (animal != null) Text('Animal : $animal', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _ink)),
          if (notes.isNotEmpty) Text('Demande : $notes', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _ambre)),
          if (_contratEnAttente(r))
            const Text('Contrat en attente de signature', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _ambre)),
          const SizedBox(height: 10),
          // Dossier de la séance : chaque module garde son propre statut
          // (une galerie livrée n'est pas une facture payée).
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: kDashBorder)),
            child: Column(children: [
              for (final l in [
                ('Devis', _etatDevis(r), _devisSeances.any((x) => x['rdv_id']?.toString() == r['id']?.toString()) ? 'Voir' : 'Créer',
                    () { Navigator.pop(ctx); _devisSeances.any((x) => x['rdv_id']?.toString() == r['id']?.toString()) ? _go(const DevisPage()) : _nouveauDevis(r); }),
                ('Contrat', _etatContrat(r), 'Voir', () { Navigator.pop(ctx); _go(const PhotographeContratsPage()); }),
                ('Galerie', _etatGalerie(r), galerie == null ? 'Créer' : 'Ouvrir', () { Navigator.pop(ctx); _ouvrirGalerie(r); }),
                ('Facture', _etatFacture(r), _facturesSeances.any((x) => x['source_rdv_id']?.toString() == r['id']?.toString() && x['statut'] != 'annulee') ? 'Voir' : 'Facturer',
                    () { Navigator.pop(ctx); _facturesSeances.any((x) => x['source_rdv_id']?.toString() == r['id']?.toString() && x['statut'] != 'annulee') ? _go(const FacturationPage()) : _facturer(r); }),
              ])
                Row(children: [
                  SizedBox(width: 64, child: Text(l.$1, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: _ink))),
                  Expanded(child: Text(l.$2.texte, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: l.$2.c))),
                  TextButton(onPressed: l.$4, child: Text(l.$3, style: const TextStyle(fontFamily: 'Galey', color: _teal))),
                ]),
            ]),
          ),
          const SizedBox(height: 6),
          if ((r['client_uid']?.toString() ?? '').isNotEmpty)
            action(ctx, Icons.chat_bubble_outline, 'Contacter le client', () => _message(r)),
          if (lieu.isNotEmpty) action(ctx, Icons.directions_outlined, "Itinéraire jusqu'au lieu", () => _naviguer(lieu)),
          action(ctx, Icons.event_note_outlined, "Voir la séance dans l'agenda",
              () => _go(ProAgendaPage(initialTabIndex: 1, focusRdvId: r['id']?.toString()))),
        ]),
      )),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator(color: _teal)));
    }
    final now = DateTime.now();
    final semaine = _seances.where((r) => _debut(r).isBefore(now.add(const Duration(days: 7)))).length;
    final aLivrer = _galeries.where((g) => kGaleriesALivrer.contains(_statut(g))).toList();
    final selections = _galeries.where((g) => _statut(g) == 'selection_recue').toList();
    return LayoutBuilder(builder: (context, c) {
      final large = c.maxWidth >= 860;
      void versGaleries() {
        final ctx = _galeriesKey.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
      }
      final principale = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DashCarte(child: _seancesSection()),
        const SizedBox(height: 16),
        DashCarte(key: _galeriesKey, child: _galeriesSection()),
      ]);
      final secondaire = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _aTraiterSection(),
        _devisSection(),
      ]);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GridView.count(
          crossAxisCount: large ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12, mainAxisSpacing: 12,
          childAspectRatio: large ? 2.1 : 1.65,
          children: [
            DashKpi(valeur: semaine, label: 'Séances à venir (7 jours)', icon: Icons.photo_camera_outlined,
                onTap: () => _go(const ProAgendaPage(initialTabIndex: 1))),
            DashKpi(valeur: aLivrer.length, label: 'Galeries à livrer', icon: Icons.photo_library_outlined, teinte: _violet,
                actif: aLivrer.isNotEmpty, onTap: versGaleries),
            DashKpi(valeur: _devis.length, label: 'Devis en attente', icon: Icons.request_quote_outlined, teinte: _ambre,
                actif: _devis.isNotEmpty, onTap: () => _go(const DevisPage())),
            DashKpi(valeur: selections.length, label: 'Sélections à traiter', icon: Icons.favorite_border, teinte: _vert,
                actif: selections.isNotEmpty, onTap: versGaleries),
          ],
        ),
        const SizedBox(height: 16),
        if (large)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: principale),
            const SizedBox(width: 16),
            Expanded(child: secondaire),
          ])
        else ...[
          DashCarte(child: _seancesSection()),
          const SizedBox(height: 16),
          DashCarte(key: _galeriesKey, child: _galeriesSection()),
          const SizedBox(height: 16),
          secondaire,
        ],
        const SizedBox(height: 16),
        _accesRapides(versGaleries),
      ]);
    });
  }

  Widget _discret(String t) => Padding(padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(t, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)));

  Widget _seancesSection() {
    final liste = _seances.take(8).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Prochaines séances', icone: Icons.calendar_today_outlined, compteur: _seances.length,
          trailing: DashLien("Voir l'agenda", onTap: () => _go(const ProAgendaPage(initialTabIndex: 1)))),
      const SizedBox(height: 6),
      if (liste.isEmpty) _discret('Aucune séance programmée dans les 30 prochains jours.'),
      for (final r in liste)
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _actions(r),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F1EF)))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 74, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_jour(_debut(r)), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12.5, color: _ink)),
                Text('${_hm(_debut(r))} · ${(r['duree_minutes'] as num?)?.toInt() ?? 60} min',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _muted)),
              ])),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_prestation(r), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
                Text([_nomClient(r), if (_animal(r) != null) _animal(r)!].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
                if ((r['lieu']?.toString() ?? '').trim().isNotEmpty)
                  Text(r['lieu'].toString().trim(), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
              ])),
              const SizedBox(width: 6),
              _contratEnAttente(r)
                  ? const DashBadge('Contrat à signer', fg: _ambre, bg: Color(0xFFFFF4DC))
                  : const DashBadge('Confirmée', fg: Color(0xFF1D4ED8), bg: Color(0xFFE8F0FE)),
            ]),
          ),
        ),
    ]);
  }

  String _depuis(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    final j = DateTime.now().difference(d).inDays;
    return j <= 0 ? "aujourd'hui" : j == 1 ? 'hier' : 'il y a $j jours';
  }

  Widget _galeriesSection() {
    final enCours = _galeries.where((g) => _statut(g) != 'archivee' && _statut(g) != 'livree').toList();
    final liste = (enCours.isEmpty ? _galeries.where((g) => _statut(g) != 'archivee').toList() : enCours).take(8).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Galeries en cours', icone: Icons.photo_library_outlined, compteur: enCours.length,
          trailing: DashLien('Toutes les galeries', onTap: () => _go(const PhotographeGaleriesPage()))),
      const SizedBox(height: 6),
      if (!_statutDispo)
        const Padding(padding: EdgeInsets.only(bottom: 6),
            child: Text('Migration migration_photographe_galeries_statut.sql à passer pour suivre les statuts.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _ambre))),
      if (liste.isEmpty) _discret('Aucune galerie. Créez-la depuis une séance ou depuis Mes galeries.'),
      for (final g in liste)
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _go(PhotographeAlbumPage(albumId: g['id'].toString(), clientName: _nomClient(g))),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F1EF)))),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g['titre']?.toString() ?? 'Galerie', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
                Text([
                  _nomClient(g),
                  if (g['date_seance'] != null) () { final d = DateTime.tryParse(g['date_seance'].toString()); return d == null ? '' : 'séance du ${_jour(d)}'; }(),
                  '${_nbPhotos[g['id'].toString()] ?? 0} photo${(_nbPhotos[g['id'].toString()] ?? 0) > 1 ? 's' : ''}',
                ].where((x) => x.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
                Text('Dernière activité : ${_depuis((g['updated_at'] ?? g['created_at'])?.toString())}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
              ])),
              const SizedBox(width: 6),
              Builder(builder: (_) { final st = styleGalerie(_statut(g)); return DashBadge(st.label, fg: st.fg, bg: st.bg); }),
            ]),
          ),
        ),
    ]);
  }

  Widget _aTraiterSection() {
    final now = DateTime.now();
    final sansGalerie = _passees.where((r) => _galerieDe(r) == null).toList();
    final selections = _galeries.where((g) => _statut(g) == 'selection_recue').toList();
    final contrats = _contratsAttente.where((c) {
      final r = [..._seances, ..._passees].where((x) => x['id']?.toString() == c['rdv_id']?.toString()).firstOrNull;
      return r == null || _debut(r).isAfter(now.subtract(const Duration(days: 30)));
    }).toList();
    final alertes = <(IconData, String, VoidCallback, Color)>[
      if (_demandes.isNotEmpty)
        (Icons.mark_email_unread_outlined, '${_demandes.length} demande${_demandes.length > 1 ? 's' : ''} de séance à confirmer',
            () => _go(const ProAgendaPage(initialTabIndex: 0)), _ambre),
      for (final g in selections)
        (Icons.favorite_border, 'Sélection reçue — ${g['titre'] ?? 'galerie'}',
            () => _go(PhotographeAlbumPage(albumId: g['id'].toString(), clientName: _nomClient(g))), _vert),
      for (final r in sansGalerie.take(4))
        (Icons.add_photo_alternate_outlined, 'Galerie à créer — séance du ${_jour(_debut(r))}, ${_nomClient(r)}', () => _ouvrirGalerie(r), _violet),
      if (contrats.isNotEmpty)
        (Icons.description_outlined, '${contrats.length} contrat${contrats.length > 1 ? 's' : ''} en attente de signature',
            () => _go(const PhotographeContratsPage()), _ambre),
    ];
    if (alertes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DashTitre('À traiter', icone: Icons.notifications_none, compteur: alertes.length),
        const SizedBox(height: 4),
        for (final a in alertes.take(7))
          InkWell(
            onTap: a.$3,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                Icon(a.$1, size: 18, color: a.$4),
                const SizedBox(width: 10),
                Expanded(child: Text(a.$2, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _ink))),
                const Icon(Icons.chevron_right, size: 18, color: _muted),
              ]),
            ),
          ),
      ])),
    );
  }

  Widget _devisSection() {
    if (_devis.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DashTitre('Devis en attente', icone: Icons.request_quote_outlined, compteur: _devis.length,
            trailing: DashLien('Tous les devis', onTap: () => _go(const DevisPage()))),
        const SizedBox(height: 4),
        for (final d in _devis.take(5))
          InkWell(
            onTap: () => _go(const DevisPage()),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_nomClient(d), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13.5, color: _ink)),
                  Text('${d['numero_devis'] ?? 'Devis'} · envoyé ${_depuis(d['date_devis']?.toString())}',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
                ])),
                Text('${((d['total_ttc'] as num?) ?? 0).toStringAsFixed(0)} €',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5, color: _ink)),
              ]),
            ),
          ),
      ])),
    );
  }

  Widget _accesRapides(VoidCallback versGaleries) {
    Widget tuile(IconData ic, String t, VoidCallback onTap) => Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: kDashBorder)),
              child: Row(children: [
                Icon(ic, size: 19, color: _teal),
                const SizedBox(width: 8),
                Expanded(child: Text(t, maxLines: 2, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5,
                    fontWeight: FontWeight.w600, color: _ink))),
              ]),
            ),
          ),
        );
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Accès rapides', icone: Icons.bolt_outlined,
          trailing: DashLien('Statistiques', onTap: () => _go(const PhotographeDashboardPage()))),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 560 ? 4 : 2;
        return GridView.count(
          crossAxisCount: cols, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: cols == 4 ? 3.0 : 2.9,
          children: [
            tuile(Icons.add_circle_outline, 'Nouvelle séance', () => _go(const ProAgendaPage(initialTabIndex: 1, nouveauRdv: true))),
            tuile(Icons.photo_library_outlined, 'Mes galeries', () => _go(const PhotographeGaleriesPage())),
            tuile(Icons.request_quote_outlined, 'Créer un devis', () => _go(const DevisPage())),
            tuile(Icons.receipt_long_outlined, 'Facturation', () => _go(const FacturationPage())),
          ],
        );
      }),
    ]));
  }
}
