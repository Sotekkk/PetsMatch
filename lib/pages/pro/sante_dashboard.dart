// Accueil ostéopathe animalier / santé : tableau de bord de l'activité.
// Uniquement des données réelles (rdv, suivis_morpho, animal_access) ; chaque
// élément ouvre le module existant (agenda, Mes patients, Mes suivis, compte
// rendu, messagerie). Mêmes briques que le tableau vétérinaire
// (widgets/dashboard/dashboard_kit.dart). Miroir site :
// website/src/components/dashboard/SanteDashboard.tsx.
//
// Extérieur (domicile, écurie, élevage…) = RDV avec une adresse
// d'intervention (rdv.lieu, sans salle) ou des coordonnées (lieu_lat) — même
// règle que l'agenda. L'adresse du propriétaire n'est jamais supposée.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/animaux/morpho/morpho_constants.dart' show labelTypeSuivi;
import 'package:PetsMatch/pages/animaux/morpho/morpho_detail_page.dart';
import 'package:PetsMatch/pages/message.dart';
import 'package:PetsMatch/pages/pro/compte_rendu_page.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/pro/pro_clients_page.dart';
import 'package:PetsMatch/pages/pro/sante_suivis_morpho_page.dart';
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';

const _teal = kDashTeal;
const _ink = kDashInk;
const _muted = kDashMuted;
const _vertDomicile = Color(0xFF2E7D5E);
const _violetSuivi = Color(0xFF7B5EA7);
const _ambre = Color(0xFFD97706);

bool estExterieur(Map<String, dynamic> r) =>
    ((r['lieu']?.toString().trim() ?? '').isNotEmpty && r['salle_id'] == null) || r['lieu_lat'] != null;

/// Statut affiché : « En cours » / « À venir » / « Confirmé » (passé) calculés.
({String label, Color fg, Color bg}) statutRdvSante(Map<String, dynamic> r, DateTime now) {
  final s = r['statut']?.toString() ?? '';
  final debut = DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal() ?? now;
  final fin = debut.add(Duration(minutes: (r['duree_minutes'] as num?)?.toInt() ?? 45));
  switch (s) {
    case 'demande':
    case 'contre_proposition':
      return (label: 'En attente', fg: const Color(0xFF8A5A00), bg: const Color(0xFFFFF4DC));
    case 'termine':
      return (label: 'Terminé', fg: const Color(0xFF4B5563), bg: const Color(0xFFF1F2F4));
    case 'annule':
    case 'refuse':
      return (label: 'Annulé', fg: const Color(0xFF9CA3AF), bg: const Color(0xFFF7F7F8));
    case 'confirme':
      if (now.isBefore(debut)) return (label: 'À venir', fg: const Color(0xFF1D4ED8), bg: const Color(0xFFE8F0FE));
      if (now.isBefore(fin)) return (label: 'En cours', fg: _teal, bg: const Color(0xFFE6F2F3));
      return (label: 'Confirmé', fg: const Color(0xFF2E7D5E), bg: const Color(0xFFE8F5EE));
  }
  return (label: s, fg: _muted, bg: const Color(0xFFF1F2F4));
}

class SanteDashboard extends StatefulWidget {
  /// Même règle que la liste « Mes patients » (calculée par l'accueil).
  final int patientsCount;
  const SanteDashboard({super.key, required this.patientsCount});

  @override
  State<SanteDashboard> createState() => _SanteDashboardState();
}

class _SanteDashboardState extends State<SanteDashboard> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _rdvs = [];
  List<Map<String, dynamic>> _suivisAPrevoir = [];
  bool _suivisDispo = true; // colonne prochain_controle présente ?
  final Map<String, String> _clients = {};
  final Map<String, Map<String, dynamic>> _animaux = {};
  DateTime _jour = DateTime.now();
  String _filtreLieu = 'tous'; // tous | cabinet | domicile
  String _periode = 'mois';
  RealtimeChannel? _canal;
  final _planningKey = GlobalKey();

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
    final pid = _pid;
    if (pid.isNotEmpty) {
      // Compteurs à jour quand un RDV change (demande, confirmation…).
      _canal = _supa.channel('dash-sante-$pid')
        ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'rdv',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'pro_profile_id', value: pid),
            callback: (_) { if (mounted) _charger(); })
        ..subscribe();
    }
  }

  @override
  void dispose() {
    if (_canal != null) _supa.removeChannel(_canal!);
    super.dispose();
  }

  Future<void> _charger() async {
    final pid = _pid;
    if (pid.isEmpty) { setState(() => _loading = false); return; }
    final now = DateTime.now();
    final debutAnnee = DateTime(now.year, 1, 1);
    final lundi = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final depuis = lundi.isBefore(debutAnnee) ? lundi : debutAnnee;
    try {
      final rows = await _supa.from('rdv')
          .select('id, date_heure, duree_minutes, statut, motif, animal_id, client_uid, client_profile_id, '
              'client_nom_manuel, animal_nom_manuel, lieu, lieu_lat, lieu_lng, salle_id, notes_client, created_at, termine_at')
          .eq('pro_profile_id', pid)
          .or('date_heure.gte.${depuis.toUtc().toIso8601String()},statut.in.(demande,contre_proposition,confirme)')
          .order('date_heure');
      _rdvs = List<Map<String, dynamic>>.from((rows as List).map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) {}
    await _chargerSuivis(pid, now);
    await _chargerNoms();
    if (mounted) setState(() => _loading = false);
  }

  /// Suivis à prévoir : dernier suivi de chaque animal portant une date de
  /// contrôle conseillée (saisie par le praticien) dans les 30 jours ou
  /// dépassée. Jamais d'échéance calculée.
  Future<void> _chargerSuivis(String pid, DateTime now) async {
    try {
      final rows = await _supa.from('suivis_morpho')
          .select('id, animal_id, animal_nom_libre, espece_libre, type_suivi, date, prochain_controle, motif')
          .eq('pro_profile_id', pid).order('date', ascending: false);
      final dernier = <String, Map<String, dynamic>>{};
      for (final r in rows as List) {
        final cle = r['animal_id']?.toString() ?? 'libre:${r['id']}';
        dernier.putIfAbsent(cle, () => Map<String, dynamic>.from(r as Map));
      }
      final limite = DateTime(now.year, now.month, now.day).add(const Duration(days: 30));
      _suivisAPrevoir = dernier.values.where((s) {
        final d = DateTime.tryParse(s['prochain_controle']?.toString() ?? '');
        return d != null && !d.isAfter(limite);
      }).toList()
        ..sort((a, b) => a['prochain_controle'].toString().compareTo(b['prochain_controle'].toString()));
      _suivisDispo = true;
    } catch (_) {
      // Migration migration_suivis_prochain_controle.sql pas encore passée.
      _suivisAPrevoir = [];
      _suivisDispo = false;
    }
  }

  Future<void> _chargerNoms() async {
    final profils = {for (final r in _rdvs) if (r['client_profile_id'] != null) r['client_profile_id'].toString()};
    final animaux = {
      for (final r in _rdvs) if (r['animal_id'] != null) r['animal_id'].toString(),
      for (final s in _suivisAPrevoir) if (s['animal_id'] != null) s['animal_id'].toString(),
    };
    try {
      if (profils.isNotEmpty) {
        final rows = await _supa.from('user_profiles_complet')
            .select('id, firstname, lastname, nom, profile_type').inFilter('id', profils.toList());
        for (final p in rows as List) {
          // Structure (écurie, élevage) : nom du profil ; particulier : prénom nom.
          final perso = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
          final structure = (p['nom']?.toString() ?? '').trim();
          _clients[p['id'].toString()] = p['profile_type'] != 'particulier' && structure.isNotEmpty
              ? structure : (perso.isNotEmpty ? perso : structure);
        }
      }
    } catch (_) {}
    try {
      if (animaux.isNotEmpty) {
        final rows = await _supa.from('animaux').select('id, nom, espece, photo_url').inFilter('id', animaux.toList());
        for (final a in rows as List) {
          _animaux[a['id'].toString()] = Map<String, dynamic>.from(a as Map);
        }
      }
    } catch (_) {}
  }

  // ── Sélections ──────────────────────────────────────────────────────────

  DateTime _debut(Map<String, dynamic> r) =>
      DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal() ?? DateTime(2000);
  bool _memeJour(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  bool _actif(Map<String, dynamic> r) =>
      const ['confirme', 'termine', 'demande', 'contre_proposition'].contains(r['statut']);

  List<Map<String, dynamic>> _duJour(DateTime j) =>
      _rdvs.where((r) => _memeJour(_debut(r), j)).toList()..sort((a, b) => _debut(a).compareTo(_debut(b)));

  List<Map<String, dynamic>> get _demandes =>
      _rdvs.where((r) => r['statut'] == 'demande' || r['statut'] == 'contre_proposition').toList()
        ..sort((a, b) => (b['created_at']?.toString() ?? '').compareTo(a['created_at']?.toString() ?? ''));

  String _nomClient(Map<String, dynamic> r) {
    final n = _clients[r['client_profile_id']?.toString() ?? ''];
    if (n != null && n.isNotEmpty) return n;
    final m = r['client_nom_manuel']?.toString() ?? '';
    return m.isNotEmpty ? m : 'Client';
  }

  String _nomAnimal(Map<String, dynamic> r) {
    final n = _animaux[r['animal_id']?.toString()]?['nom']?.toString() ?? '';
    if (n.isNotEmpty) return n;
    final m = (r['animal_nom_manuel'] ?? r['animal_nom_libre'])?.toString() ?? '';
    return m.isNotEmpty ? m : 'Animal non précisé';
  }

  String? _photo(Map<String, dynamic> r) => _animaux[r['animal_id']?.toString()]?['photo_url']?.toString();

  String _lieuCourt(Map<String, dynamic> r) {
    if (!estExterieur(r)) return 'Cabinet';
    final a = r['lieu']?.toString().trim() ?? '';
    return a.isEmpty || a.toLowerCase() == 'à domicile' ? 'Domicile — adresse non renseignée' : 'Domicile · $a';
  }

  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _jm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  static const _jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
  static const _mois = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août',
      'septembre', 'octobre', 'novembre', 'décembre'];
  String _dateLongue(DateTime d) => '${_jours[d.weekday - 1]} ${d.day} ${_mois[d.month - 1]}';

  /// Prochain déplacement : prochain RDV extérieur confirmé (en cours ou à
  /// venir) + les autres RDV du même jour à la même adresse (plusieurs
  /// animaux, chacun avec son propre RDV / dossier).
  List<Map<String, dynamic>> _prochainDeplacement(DateTime now) {
    final candidats = _rdvs.where((r) {
      if (r['statut'] != 'confirme' || !estExterieur(r)) return false;
      final fin = _debut(r).add(Duration(minutes: (r['duree_minutes'] as num?)?.toInt() ?? 45));
      return fin.isAfter(now);
    }).toList()..sort((a, b) => _debut(a).compareTo(_debut(b)));
    if (candidats.isEmpty) return [];
    final premier = candidats.first;
    bool memeLieu(Map<String, dynamic> a, Map<String, dynamic> b) {
      final la = (a['lieu_lat'] as num?)?.toDouble(), lb = (b['lieu_lat'] as num?)?.toDouble();
      final ga = (a['lieu_lng'] as num?)?.toDouble(), gb = (b['lieu_lng'] as num?)?.toDouble();
      if (la != null && lb != null && ga != null && gb != null) {
        return (la - lb).abs() < 0.0015 && (ga - gb).abs() < 0.0015; // ~150 m
      }
      final ta = a['lieu']?.toString().trim().toLowerCase() ?? '';
      return ta.isNotEmpty && ta == (b['lieu']?.toString().trim().toLowerCase() ?? '');
    }
    return candidats.where((r) => _memeJour(_debut(r), _debut(premier)) && memeLieu(r, premier)).toList();
  }

  Future<void> _itineraire(Map<String, dynamic> r) async {
    final lat = (r['lieu_lat'] as num?)?.toDouble(), lng = (r['lieu_lng'] as num?)?.toDouble();
    final adresse = r['lieu']?.toString().trim() ?? '';
    if (lat == null && adresse.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Adresse d\'intervention non renseignée pour ce rendez-vous.', style: TextStyle(fontFamily: 'Galey'))));
      return;
    }
    final dest = lat != null && lng != null ? '$lat,$lng' : Uri.encodeComponent(adresse);
    await launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$dest'),
        mode: LaunchMode.externalApplication);
  }

  // ── Navigation vers les modules existants ───────────────────────────────

  Future<void> _go(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _charger();
  }

  void _ouvrirRdv(Map<String, dynamic> r) {
    final s = r['statut'];
    final futur = _debut(r).isAfter(DateTime.now());
    final onglet = (s == 'demande' || s == 'contre_proposition') ? 0 : (s == 'confirme' && futur ? 1 : 2);
    _go(ProAgendaPage(initialTabIndex: onglet, focusRdvId: r['id']?.toString()));
  }

  void _ouvrirSuivi(Map<String, dynamic> s) {
    final a = _animaux[s['animal_id']?.toString()];
    _go(MorphoDetailPage(suivi: {...s, '_animal_nom': _nomAnimal(s)},
        espece: (a?['espece'] ?? s['espece_libre'] ?? 'chien').toString(), readOnly: false));
  }

  /// Rédiger un compte rendu : choix du patient (RDV du pro + accès accordés).
  Future<void> _choisirPatientCr() async {
    final ids = <String>{
      for (final r in _rdvs) if (r['animal_id'] != null && (r['statut'] == 'confirme' || r['statut'] == 'termine')) r['animal_id'].toString(),
    };
    try {
      final g = await _supa.from('animal_access').select('animal_id')
          .eq('pro_profile_id', _pid).inFilter('statut', ['active', 'active_write']);
      for (final x in g as List) { if (x['animal_id'] != null) ids.add(x['animal_id'].toString()); }
    } catch (_) {}
    List<Map<String, dynamic>> patients = [];
    if (ids.isNotEmpty) {
      try {
        final rows = await _supa.from('animaux').select('id, nom, espece, photo_url').inFilter('id', ids.toList()).order('nom');
        patients = List<Map<String, dynamic>>.from(rows as List);
      } catch (_) {}
    }
    if (!mounted) return;
    if (patients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucun patient pour l\'instant : un compte rendu se rédige pour un animal suivi.', style: TextStyle(fontFamily: 'Galey'))));
      return;
    }
    final choisi = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.6, maxChildSize: 0.9,
        builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
          const Text('Compte rendu — choisir le patient', style: TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final p in patients)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: DashPhotoAnimal(url: p['photo_url']?.toString()),
              title: Text(p['nom']?.toString() ?? 'Animal', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              subtitle: Text(p['espece']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
              onTap: () => Navigator.pop(ctx, p),
            ),
        ]),
      ),
    );
    if (choisi != null && mounted) {
      _go(CompteRenduPage(animalId: choisi['id']?.toString(), clientName: choisi['nom']?.toString() ?? '', categoryColor: _teal));
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator(color: _teal)));
    }
    final now = DateTime.now();
    final aujourdhui = _duJour(now).where(_actif).toList();
    final domicileAuj = aujourdhui.where(estExterieur).length;
    final deplacement = _prochainDeplacement(now);
    return LayoutBuilder(builder: (context, c) {
      final large = c.maxWidth >= 860;
      final planning = DashCarte(key: _planningKey, child: _planningSection(now));
      final colonne = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _deplacementSection(deplacement),
        const SizedBox(height: 16),
        _demandesSection(now),
        const SizedBox(height: 16),
        _suivisSection(now),
      ]);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GridView.count(
          crossAxisCount: large ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12, mainAxisSpacing: 12,
          childAspectRatio: large ? 2.1 : 1.65,
          children: [
            DashKpi(valeur: aujourdhui.length, label: "RDV aujourd'hui", icon: Icons.today_outlined,
                onTap: () => _go(const ProAgendaPage(initialTabIndex: 1))),
            DashKpi(valeur: domicileAuj, label: 'Visites à domicile', icon: Icons.home_outlined, teinte: _vertDomicile,
                actif: _filtreLieu == 'domicile' && _memeJour(_jour, now),
                onTap: () {
                  setState(() { _jour = now; _filtreLieu = 'domicile'; });
                  final ctx = _planningKey.currentContext;
                  if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
                }),
            DashKpi(valeur: _suivisAPrevoir.length, label: 'Suivis à prévoir', icon: Icons.event_repeat_outlined,
                teinte: _violetSuivi, onTap: () => _go(const SanteSuivisMorphoPage())),
            DashKpi(valeur: _demandes.length, label: 'Demandes en attente', icon: Icons.schedule_outlined,
                teinte: _ambre, onTap: () => _go(const ProAgendaPage(initialTabIndex: 0))),
          ],
        ),
        const SizedBox(height: 16),
        if (large)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: planning),
            const SizedBox(width: 16),
            Expanded(child: colonne),
          ])
        else ...[
          planning,
          const SizedBox(height: 16),
          colonne,
        ],
        const SizedBox(height: 16),
        _statsSection(now),
        const SizedBox(height: 16),
        _accesRapides(deplacement),
      ]);
    });
  }

  Widget _choix(String t, bool actif, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5,
              color: actif ? Colors.white : _ink, fontWeight: FontWeight.w600)),
          selected: actif, onSelected: (_) => onTap(),
          selectedColor: _teal, backgroundColor: const Color(0xFFF1F4F3),
          showCheckmark: false, side: BorderSide.none, visualDensity: VisualDensity.compact,
        ),
      );

  // Planning du jour ------------------------------------------------------

  Widget _planningSection(DateTime now) {
    final duJour = _duJour(_jour);
    final cabinet = duJour.where((r) => !estExterieur(r)).toList();
    final domicile = duJour.where(estExterieur).toList();
    final liste = _filtreLieu == 'cabinet' ? cabinet : _filtreLieu == 'domicile' ? domicile : duJour;
    final estAujourdhui = _memeJour(_jour, now);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Planning du jour', icone: Icons.calendar_today_outlined,
          trailing: DashLien("Voir l'agenda complet", onTap: () => _go(const ProAgendaPage(initialTabIndex: 1)))),
      const SizedBox(height: 6),
      Row(children: [
        IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.chevron_left, color: _teal),
            onPressed: () => setState(() => _jour = _jour.subtract(const Duration(days: 1)))),
        Expanded(child: GestureDetector(
          onTap: estAujourdhui ? null : () => setState(() => _jour = now),
          child: Text(estAujourdhui ? "Aujourd'hui · ${_dateLongue(_jour)}" : _dateLongue(_jour),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w600, color: _ink)),
        )),
        IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.chevron_right, color: _teal),
            onPressed: () => setState(() => _jour = _jour.add(const Duration(days: 1)))),
      ]),
      Row(children: [
        _choix('Tous (${duJour.length})', _filtreLieu == 'tous', () => setState(() => _filtreLieu = 'tous')),
        _choix('Cabinet (${cabinet.length})', _filtreLieu == 'cabinet', () => setState(() => _filtreLieu = 'cabinet')),
        _choix('Domicile (${domicile.length})', _filtreLieu == 'domicile', () => setState(() => _filtreLieu = 'domicile')),
      ]),
      const SizedBox(height: 8),
      if (liste.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(duJour.isEmpty ? 'Aucun rendez-vous ce jour.' : 'Aucun rendez-vous pour ce filtre.',
              textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Galey', color: _muted)),
        )
      else
        for (final r in liste) _ligneRdv(r, now),
    ]);
  }

  Widget _ligneRdv(Map<String, dynamic> r, DateTime now) {
    final st = statutRdvSante(r, now);
    final annule = st.label == 'Annulé';
    final duree = (r['duree_minutes'] as num?)?.toInt() ?? 45;
    final motif = (r['motif']?.toString() ?? '').trim();
    final ext = estExterieur(r);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _ouvrirRdv(r),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F1EF)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 50,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_hm(_debut(r)), style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14,
                  color: annule ? _muted : _ink, decoration: annule ? TextDecoration.lineThrough : null)),
              Text('$duree min', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _muted)),
            ]),
          ),
          DashPhotoAnimal(url: _photo(r)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_nomAnimal(r), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: annule ? _muted : _ink)),
              Text([_nomClient(r), if (motif.isNotEmpty) motif].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
              const SizedBox(height: 2),
              Row(children: [
                Icon(ext ? Icons.home_outlined : Icons.storefront_outlined, size: 13, color: ext ? _vertDomicile : _muted),
                const SizedBox(width: 3),
                Flexible(child: Text(_lieuCourt(r), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: ext ? _vertDomicile : _muted))),
              ]),
            ]),
          ),
          const SizedBox(width: 6),
          DashBadge(st.label, fg: st.fg, bg: st.bg),
        ]),
      ),
    );
  }

  // Prochain déplacement --------------------------------------------------

  Widget _deplacementSection(List<Map<String, dynamic>> groupe) {
    if (groupe.isEmpty) {
      return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: const [
        DashTitre('Prochain déplacement', icone: Icons.place_outlined),
        SizedBox(height: 10),
        Text('Aucun rendez-vous extérieur à venir.', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)),
      ]));
    }
    final r = groupe.first;
    final adresse = r['lieu']?.toString().trim() ?? '';
    final sansAdresse = adresse.isEmpty && r['lieu_lat'] == null;
    final infos = (r['notes_client']?.toString() ?? '').trim();
    final now = DateTime.now();
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Prochain déplacement', icone: Icons.place_outlined),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_hm(_debut(r)), style: const TextStyle(fontFamily: 'Galey', fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_memeJour(_debut(r), now) ? '' : '${_jm(_debut(r))} · '}${_nomClient(r)}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
          const SizedBox(height: 2),
          Text(sansAdresse ? 'Adresse d\'intervention non renseignée' : (adresse.isNotEmpty ? adresse : 'Position enregistrée'),
              style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: sansAdresse ? _ambre : _muted)),
          const SizedBox(height: 4),
          Text(groupe.length > 1
                  ? '${groupe.length} animaux : ${groupe.map(_nomAnimal).join(', ')}'
                  : _nomAnimal(r),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _ink)),
          if (infos.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Infos : $infos', maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
          ],
        ])),
      ]),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: sansAdresse ? null : () => _itineraire(r),
        icon: const Icon(Icons.directions_outlined, size: 18),
        label: const Text('Voir l\'itinéraire', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: _teal, side: const BorderSide(color: Color(0xFFCFDCDD)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ]));
  }

  // Demandes en attente ---------------------------------------------------

  String _quand(String? iso, DateTime now) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    final j = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    return j == 0 ? "Aujourd'hui" : j == 1 ? 'Hier' : _jm(d);
  }

  Widget _ligneMini({required String? photo, required String titre, required String detail,
      required String droite, Color droiteCouleur = _muted, required VoidCallback onTap}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            DashPhotoAnimal(url: photo, taille: 32),
            const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titre, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _ink)),
              Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
            ])),
            const SizedBox(width: 6),
            Text(droite, style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: droiteCouleur, fontWeight: FontWeight.w600)),
            const Icon(Icons.chevron_right, size: 18, color: _muted),
          ]),
        ),
      );

  Widget _demandesSection(DateTime now) {
    final d = _demandes;
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Demandes en attente', icone: Icons.notifications_none, compteur: d.length,
          trailing: d.isEmpty ? null : DashLien('Voir toutes', onTap: () => _go(const ProAgendaPage(initialTabIndex: 0)))),
      const SizedBox(height: 6),
      if (d.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Aucune demande à traiter.', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)))
      else
        for (final r in d.take(3))
          _ligneMini(
            photo: _photo(r), titre: '${_nomAnimal(r)} · ${_nomClient(r)}',
            detail: [
              (r['motif']?.toString() ?? '').trim().isEmpty ? 'Rendez-vous' : r['motif'].toString().trim(),
              'pour le ${_jm(_debut(r))} ${_hm(_debut(r))}',
              if (estExterieur(r)) _lieuCourt(r),
            ].join(' · '),
            droite: _quand(r['created_at']?.toString(), now), droiteCouleur: const Color(0xFFDC2626),
            onTap: () => _ouvrirRdv(r),
          ),
    ]));
  }

  // Suivis à prévoir ------------------------------------------------------

  Widget _suivisSection(DateTime now) {
    final s = _suivisAPrevoir;
    final jour = DateTime(now.year, now.month, now.day);
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Suivis à prévoir', icone: Icons.event_repeat_outlined, compteur: s.length,
          trailing: DashLien('Voir tous', onTap: () => _go(const SanteSuivisMorphoPage()))),
      const SizedBox(height: 6),
      if (!_suivisDispo)
        const Text('Indiquez un « prochain contrôle conseillé » dans vos suivis pour les retrouver ici.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _muted))
      else if (s.isEmpty)
        const Text('Aucun contrôle conseillé dans les 30 prochains jours.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted))
      else
        for (final x in s.take(3)) () {
          final d = DateTime.parse(x['prochain_controle'].toString());
          final ecart = DateTime(d.year, d.month, d.day).difference(jour).inDays;
          final derniere = DateTime.tryParse(x['date']?.toString() ?? '');
          return _ligneMini(
            photo: _photo(x), titre: _nomAnimal(x),
            detail: [labelTypeSuivi(x['type_suivi']?.toString()),
              if (derniere != null) 'dernière séance ${_jm(derniere)}'].join(' · '),
            droite: ecart < 0 ? 'En retard' : ecart == 0 ? "Aujourd'hui" : 'Dans $ecart j',
            droiteCouleur: ecart < 0 ? const Color(0xFFDC2626) : _muted,
            onTap: () => _ouvrirSuivi(x),
          );
        }(),
    ]));
  }

  // Statistiques ------------------------------------------------------------

  Widget _statsSection(DateTime now) {
    final jour = DateTime(now.year, now.month, now.day);
    final (debut, fin) = switch (_periode) {
      'semaine' => (jour.subtract(Duration(days: now.weekday - 1)), jour.subtract(Duration(days: now.weekday - 1)).add(const Duration(days: 7))),
      'annee' => (DateTime(now.year, 1, 1), DateTime(now.year + 1, 1, 1)),
      _ => (DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 1)),
    };
    final faits = _rdvs.where((r) => (r['statut'] == 'confirme' || r['statut'] == 'termine')).toList();
    // Couleur = motif (ordre de première apparition sur l'année), pas le rang.
    final ordre = <String>[];
    String cle(Map<String, dynamic> r) {
      final m = (r['motif']?.toString() ?? '').trim();
      return m.isEmpty ? 'Sans motif' : m[0].toUpperCase() + m.substring(1);
    }
    for (final r in faits) { final k = cle(r); if (!ordre.contains(k)) ordre.add(k); }
    final periode = faits.where((r) => !_debut(r).isBefore(debut) && _debut(r).isBefore(fin)).toList();
    final parMotif = <String, int>{};
    for (final r in periode) { parMotif[cle(r)] = (parMotif[cle(r)] ?? 0) + 1; }
    // 5 motifs + « Autre » (jamais de 7e couleur générée).
    final tries = parMotif.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final garde = tries.take(5).map((e) => e.key).toSet();
    final segments = <DashSegment>[
      for (final k in ordre.where(garde.contains))
        (key: k, label: k, color: kDashPalette[math.min(ordre.where(garde.contains).toList().indexOf(k), 4)], n: parMotif[k]!),
      if (tries.length > 5)
        (key: '_autre', label: 'Autre', color: kDashPalette[5], n: tries.skip(5).fold<int>(0, (a, e) => a + e.value)),
    ];
    final cabinet = periode.where((r) => !estExterieur(r)).length;
    final domicile = periode.length - cabinet;

    final lundi = jour.subtract(Duration(days: now.weekday - 1));
    final realises = List<int>.filled(7, 0), programmes = List<int>.filled(7, 0), annules = List<int>.filled(7, 0);
    for (final r in _rdvs) {
      final d = _debut(r);
      final i = DateTime(d.year, d.month, d.day).difference(lundi).inDays;
      if (i < 0 || i > 6) continue;
      switch (r['statut']) {
        case 'termine': realises[i]++; break;
        case 'confirme': programmes[i]++; break;
        case 'annule': case 'refuse': annules[i]++; break;
      }
    }

    Widget barreLieu(String label, int n, Color c) {
      final total = cabinet + domicile;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(width: 74, child: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _ink))),
          Expanded(child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: total == 0 ? 0 : n / total, minHeight: 8,
                color: c, backgroundColor: const Color(0xFFF1F4F3)),
          )),
          SizedBox(width: 70, child: Text('$n${total == 0 ? '' : ' · ${(n * 100 / total).round()} %'}', textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700, color: _ink))),
        ]),
      );
    }

    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Répartition des rendez-vous', icone: Icons.donut_large_outlined),
      const SizedBox(height: 2),
      const Text('Par motif de réservation · RDV confirmés et terminés',
          style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'semaine', label: Text('Cette semaine')),
            ButtonSegment(value: 'mois', label: Text('Ce mois')),
            ButtonSegment(value: 'annee', label: Text('Cette année')),
          ],
          selected: {_periode},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _periode = s.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600)),
            backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? _teal : Colors.white),
            foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : _ink),
          ),
        ),
      ),
      const SizedBox(height: 14),
      if (segments.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('Aucun rendez-vous sur la période.', textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', color: _muted)))
      else ...[
        DashDonut(segments: segments),
        const SizedBox(height: 14),
        const Text('Lieu des consultations', style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
        const SizedBox(height: 6),
        barreLieu('Cabinet', cabinet, _teal),
        barreLieu('Domicile', domicile, _vertDomicile),
      ],
      const SizedBox(height: 14),
      const Divider(height: 1, color: Color(0xFFF0F1EF)),
      const SizedBox(height: 14),
      const Text('Activité de la semaine', style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
      const Text('RDV par jour', style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
      const SizedBox(height: 10),
      DashBarresSemaine(
        series: [realises, programmes, annules],
        couleurs: const [Color(0xFF2E7D5E), _teal, Color(0xFFB8BEC6)],
        libelles: const ['Séances réalisées', 'Programmés', 'Annulés'],
        aujourdhui: now.weekday - 1,
      ),
    ]));
  }

  // Accès rapides -----------------------------------------------------------

  Widget _accesRapides(List<Map<String, dynamic>> deplacement) {
    Widget tuile(IconData ic, String t, VoidCallback? onTap) => Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: kDashBorder)),
              child: Row(children: [
                Icon(ic, size: 19, color: onTap == null ? const Color(0xFFB8BEC6) : _teal),
                const SizedBox(width: 8),
                Expanded(child: Text(t, maxLines: 2, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5,
                    fontWeight: FontWeight.w600, color: onTap == null ? const Color(0xFFB8BEC6) : _ink))),
              ]),
            ),
          ),
        );
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const DashTitre('Accès rapides', icone: Icons.bolt_outlined),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 560 ? 3 : 2;
        return GridView.count(
          crossAxisCount: cols, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: cols == 3 ? 3.4 : 2.9,
          children: [
            tuile(Icons.add_circle_outline, 'Nouveau RDV', () => _go(const ProAgendaPage(initialTabIndex: 1, nouveauRdv: true))),
            tuile(Icons.search, 'Rechercher un patient', () => _go(const ProClientsPage())),
            tuile(Icons.event_repeat_outlined, 'Créer un suivi', () => _go(const SanteSuivisMorphoPage())),
            tuile(Icons.edit_note, 'Rédiger un compte rendu', _choisirPatientCr),
            tuile(Icons.directions_outlined, 'Itinéraire du prochain déplacement',
                deplacement.isEmpty ? null : () => _itineraire(deplacement.first)),
            tuile(Icons.chat_bubble_outline, 'Envoyer un message', () => _go(const MessagePage())),
          ],
        );
      }),
    ]));
  }
}
