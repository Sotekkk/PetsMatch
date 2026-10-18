// Accueil toiletteur : tableau de bord du salon (activité du jour).
// Données réelles et modules EXISTANTS : agenda (rdv), catalogue
// (prestations_toilettage), employés (employes, rdv.employe_id), fiche client
// (fiches_toilettage). Suivi de la prestation par étapes horodatées sur le
// rendez-vous (migration_toilettage_suivi.sql). Les statistiques de CA restent
// sur la page « Statistiques » (ToilettageDashboardPage).
// Miroir site : website/src/components/dashboard/ToilettageDashboard.tsx.
// Scopé au profil actif (pro_profile_id).

import 'package:PetsMatch/pages/pro/toilettage_seance_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_dossier_seance.dart' show showDossierToilettage, facturerToilettage;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/utils/messaging_helper.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/pro/pro_clients_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_fiche_client_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_planning_employes_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_dashboard_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart' show FacturationPage;
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';

const _teal = kDashTeal;
const _ink = kDashInk;
const _muted = kDashMuted;
const _vert = Color(0xFF2E7D5E);
const _ambre = Color(0xFFD97706);
const _rouge = Color(0xFFB3261E);
const _violet = Color(0xFF7B5EA7);

/// Étape de la prestation, déduite des horodatages du rendez-vous.
enum EtapeToilettage { aConfirmer, attendu, arrive, enCours, pret, termine, annule, absent }

EtapeToilettage etapeToilettage(Map<String, dynamic> r) {
  final s = r['statut']?.toString();
  if (s == 'demande' || s == 'contre_proposition') return EtapeToilettage.aConfirmer;
  if (s == 'annule' || s == 'refuse') return EtapeToilettage.annule;
  if (s == 'absent') return EtapeToilettage.absent;
  if (s == 'termine') return EtapeToilettage.termine;
  if (r['pret_le'] != null) return EtapeToilettage.pret;
  if (r['prestation_debut_le'] != null) return EtapeToilettage.enCours;
  if (r['arrivee_validee_le'] != null) return EtapeToilettage.arrive;
  return EtapeToilettage.attendu;
}

({String label, Color fg, Color bg}) styleEtape(EtapeToilettage e) => switch (e) {
      EtapeToilettage.aConfirmer => (label: 'À confirmer', fg: _ambre, bg: const Color(0xFFFFF4DC)),
      EtapeToilettage.attendu => (label: 'Confirmé', fg: const Color(0xFF1D4ED8), bg: const Color(0xFFE8F0FE)),
      EtapeToilettage.arrive => (label: 'Animal arrivé', fg: _violet, bg: const Color(0xFFF1ECF8)),
      EtapeToilettage.enCours => (label: 'En cours', fg: _teal, bg: const Color(0xFFE6F2F3)),
      EtapeToilettage.pret => (label: 'Prêt à récupérer', fg: _vert, bg: const Color(0xFFE7F3EC)),
      EtapeToilettage.termine => (label: 'Terminé', fg: const Color(0xFF4B5563), bg: const Color(0xFFF1F2F4)),
      EtapeToilettage.annule => (label: 'Annulé', fg: const Color(0xFF6B7280), bg: const Color(0xFFF3F4F6)),
      EtapeToilettage.absent => (label: 'Non présenté', fg: _rouge, bg: const Color(0xFFFDECEA)),
    };

class ToilettageSalonDashboard extends StatefulWidget {
  const ToilettageSalonDashboard({super.key});
  @override
  State<ToilettageSalonDashboard> createState() => _ToilettageSalonDashboardState();
}

class _ToilettageSalonDashboardState extends State<ToilettageSalonDashboard> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _rdvs = [];
  List<Map<String, dynamic>> _demandes = [];
  final Map<String, String> _employes = {};
  final Map<String, String> _clients = {};
  final Map<String, Map<String, dynamic>> _animaux = {};
  final Map<String, String> _prestations = {};
  final Map<String, double> _prixPrestations = {};
  /// RDV déjà facturés (factures.source_rdv_id, hors annulées).
  final Set<String> _factures = {};
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
  }

  List<Map<String, dynamic>> _l(dynamic r) =>
      List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map)));

  Future<void> _charger() async {
    final pid = _pid;
    if (pid.isEmpty) { setState(() => _loading = false); return; }
    final now = DateTime.now();
    final jour = DateTime(now.year, now.month, now.day);
    try {
      // Aujourd'hui + 7 jours passés (prestations à finaliser).
      _rdvs = _l(await _supa.from('rdv').select().eq('pro_profile_id', pid)
          .inFilter('statut', ['confirme', 'termine', 'absent'])
          .gte('date_heure', jour.subtract(const Duration(days: 7)).toUtc().toIso8601String())
          .lt('date_heure', jour.add(const Duration(days: 1)).toUtc().toIso8601String())
          .order('date_heure'));
    } catch (_) {}
    try {
      _demandes = _l(await _supa.from('rdv').select().eq('pro_profile_id', pid)
          .inFilter('statut', ['demande', 'contre_proposition']).order('date_heure'));
    } catch (_) { _demandes = []; }
    try {
      final e = await _supa.from('employes').select('id, prenom, nom').eq('eleveur_profile_id', pid).eq('actif', true);
      for (final x in e as List) {
        _employes[x['id'].toString()] = '${x['prenom'] ?? ''} ${x['nom'] ?? ''}'.trim();
      }
    } catch (_) {}
    final tous = [..._rdvs, ..._demandes];
    final profils = {for (final r in tous) if (r['client_profile_id'] != null) r['client_profile_id'].toString()};
    final animaux = {for (final r in tous) if (r['animal_id'] != null) r['animal_id'].toString()};
    final prestas = {for (final r in tous) if (r['prestation_id'] != null) r['prestation_id'].toString()};
    try {
      if (profils.isNotEmpty) {
        final rows = await _supa.from('user_profiles_complet').select('id, firstname, lastname, nom, profile_type').inFilter('id', profils.toList());
        for (final p in rows as List) {
          final perso = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
          final st = (p['nom']?.toString() ?? '').trim();
          _clients[p['id'].toString()] = p['profile_type'] != 'particulier' && st.isNotEmpty ? st : (perso.isNotEmpty ? perso : st);
        }
      }
    } catch (_) {}
    try {
      if (animaux.isNotEmpty) {
        final rows = await _supa.from('animaux').select('id, nom, photo_url').inFilter('id', animaux.toList());
        for (final a in rows as List) { _animaux[a['id'].toString()] = Map<String, dynamic>.from(a as Map); }
      }
    } catch (_) {}
    try {
      if (prestas.isNotEmpty) {
        final rows = await _supa.from('prestations_toilettage').select('id, nom, prix_base').inFilter('id', prestas.toList());
        for (final p in rows as List) {
          _prestations[p['id'].toString()] = p['nom']?.toString() ?? '';
          _prixPrestations[p['id'].toString()] = (p['prix_base'] as num?)?.toDouble() ?? 0;
        }
      }
    } catch (_) {}
    _factures.clear();
    if (_rdvs.isNotEmpty) {
      try {
        for (final f in await _supa.from('factures').select('source_rdv_id, statut')
            .inFilter('source_rdv_id', _rdvs.map((r) => r['id']).toList())) {
          if (f['statut'] != 'annulee') _factures.add(f['source_rdv_id'].toString());
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Facture pré-remplie depuis la prestation (prix calculé à la réservation
  /// selon l'espèce / le gabarit, sinon prix de base du catalogue).
  /// Prix TTC affiché (HT déduit selon le régime de TVA), client et animal
  /// préremplis (toilettage_dossier_seance.dart).
  Future<void> _facturer(Map<String, dynamic> r) async {
    await facturerToilettage(context, r, nomClient: _nomClient(r), animal: _nomAnimal(r));
    if (mounted) _charger();
  }

  // ── Sélections ──────────────────────────────────────────────────────────

  DateTime _debut(Map<String, dynamic> r) => DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal() ?? DateTime(2000);
  DateTime _fin(Map<String, dynamic> r) => _debut(r).add(Duration(minutes: (r['duree_minutes'] as num?)?.toInt() ?? 60));
  bool _memeJour(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _jm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  List<Map<String, dynamic>> get _duJour {
    final j = DateTime.now();
    return _rdvs.where((r) => _memeJour(_debut(r), j)).toList()..sort((a, b) => _debut(a).compareTo(_debut(b)));
  }

  String _nomAnimal(Map<String, dynamic> r) {
    final n = _animaux[r['animal_id']?.toString()]?['nom']?.toString() ?? '';
    if (n.isNotEmpty) return n;
    final m = r['animal_nom_manuel']?.toString() ?? '';
    return m.isNotEmpty ? m : 'Animal';
  }
  String _nomClient(Map<String, dynamic> r) {
    final n = _clients[r['client_profile_id']?.toString() ?? ''];
    if (n != null && n.isNotEmpty) return n;
    final m = r['client_nom_manuel']?.toString() ?? '';
    return m.isNotEmpty ? m : 'Client';
  }
  String _prestation(Map<String, dynamic> r) =>
      _prestations[r['prestation_id']?.toString()] ?? ((r['motif']?.toString() ?? '').trim().isEmpty ? 'Prestation' : r['motif'].toString().trim());
  String? _employe(Map<String, dynamic> r) => _employes[r['employe_id']?.toString()];

  /// Deux rendez-vous du même employé qui se chevauchent aujourd'hui.
  Set<String> get _conflits {
    final res = <String>{};
    final l = _duJour.where((r) => r['employe_id'] != null && r['statut'] != 'absent').toList();
    for (var i = 0; i < l.length; i++) {
      for (var j = i + 1; j < l.length; j++) {
        if (l[i]['employe_id'] == l[j]['employe_id'] && _debut(l[i]).isBefore(_fin(l[j])) && _debut(l[j]).isBefore(_fin(l[i]))) {
          res..add(l[i]['id'].toString())..add(l[j]['id'].toString());
        }
      }
    }
    return res;
  }

  // ── Actions (étapes horodatées) ─────────────────────────────────────────

  Future<void> _go(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _charger();
  }

  Future<void> _maj(Map<String, dynamic> r, Map<String, dynamic> champs, {String? ok}) async {
    try {
      await _supa.from('rdv').update(champs).eq('id', r['id']);
      r.addAll(champs);
      if (mounted) {
        setState(() {});
        if (ok != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
            e.message.contains('column') ? 'Migration migration_toilettage_suivi.sql à passer.' : 'Erreur : ${e.message}')));
      }
    }
  }

  String get _now => DateTime.now().toUtc().toIso8601String();

  Future<void> _pret(Map<String, dynamic> r) async {
    // Prévenir le propriétaire : jamais automatique, choisi à chaque fois.
    final prevenir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Animal prêt', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Text('Prévenir le propriétaire que le toilettage de ${_nomAnimal(r)} est terminé ?',
            style: const TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Sans prévenir')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Prévenir')),
        ],
      ),
    );
    if (prevenir == null) return;
    await _maj(r, {'pret_le': _now}, ok: 'Animal prêt à récupérer');
    final ownerUid = r['client_uid']?.toString();
    if (prevenir && ownerUid != null && ownerUid.isNotEmpty) {
      try {
        await _supa.from('notifications').insert({
          'uid': ownerUid,
          'type': 'toilettage_pret',
          'title': '${_nomAnimal(r)} est prêt',
          'body': 'Le toilettage de ${_nomAnimal(r)} est terminé. Vous pouvez venir le récupérer.',
          if (r['client_profile_id'] != null) 'profile_id': r['client_profile_id'],
          'data': {'rdv_id': r['id'], if (r['animal_id'] != null) 'animalId': r['animal_id'].toString()},
          'read': false,
        });
      } catch (_) {}
    }
  }

  Future<void> _message(Map<String, dynamic> r) async {
    final uid = r['client_uid']?.toString();
    if (uid == null || uid.isEmpty) return;
    final conv = await MessagingHelper.openOrCreateConversation(otherUid: uid, categorie: 'services',
        myProfileId: _pid.isNotEmpty ? _pid : null);
    if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversationId: conv, eleveurId: uid)));
  }

  Future<void> _actions(Map<String, dynamic> r) async {
    final e = etapeToilettage(r);
    final st = styleEtape(e);
    final consignes = (r['notes_client']?.toString() ?? '').trim();
    final passe = _fin(r).isBefore(DateTime.now());
    Widget action(BuildContext ctx, IconData ic, String t, VoidCallback f, {Color? c}) => ListTile(
          contentPadding: EdgeInsets.zero, dense: true,
          leading: Icon(ic, color: c ?? _teal),
          title: Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: c ?? _ink)),
          onTap: () { Navigator.pop(ctx); f(); },
        );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            DashPhotoAnimal(url: _animaux[r['animal_id']?.toString()]?['photo_url']?.toString(), taille: 44),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_nomAnimal(r), style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
              Text('${_nomClient(r)} · ${_hm(_debut(r))} · ${(r['duree_minutes'] as num?)?.toInt() ?? 60} min',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)),
            ])),
            DashBadge(st.label, fg: st.fg, bg: st.bg),
          ]),
          const SizedBox(height: 10),
          Text(_prestation(r), style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
          if (_employe(r) != null) Text('Toiletteur : ${_employe(r)}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)),
          if (consignes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Consignes : $consignes', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _ink)),
          ],
          const SizedBox(height: 6),
          // Actions selon l'étape réelle (jamais d'action incohérente).
          if (e == EtapeToilettage.attendu) ...[
            action(ctx, Icons.login_rounded, "Animal arrivé", () => _maj(r, {'arrivee_validee_le': _now})),
            if (passe) action(ctx, Icons.person_off_outlined, 'Non présenté', () => _maj(r, {'statut': 'absent'}), c: _rouge),
          ],
          if (e == EtapeToilettage.arrive)
            action(ctx, Icons.play_arrow_rounded, 'Démarrer le toilettage', () => _maj(r, {'prestation_debut_le': _now})),
          if (e == EtapeToilettage.enCours)
            action(ctx, Icons.check_circle_outline, 'Toilettage terminé — animal prêt', () => _pret(r), c: _vert),
          if (e == EtapeToilettage.pret)
            action(ctx, Icons.logout_rounded, 'Animal récupéré — clôturer', () => _maj(r, {'statut': 'termine', 'termine_at': _now}, ok: 'Prestation clôturée')),
          // Facturation : module existant, statut propre (terminé ≠ payé).
          if ((e == EtapeToilettage.pret || e == EtapeToilettage.termine) && !_factures.contains(r['id'].toString()))
            action(ctx, Icons.receipt_long_outlined, 'Facturer la prestation', () => _facturer(r)),
          if (_factures.contains(r['id'].toString()))
            action(ctx, Icons.receipt_long_outlined, 'Prestation facturée — voir la facturation', () => _go(const FacturationPage())),
          // Fiche technique : dès que le toilettage a commencé.
          if (r['animal_id'] != null && const {EtapeToilettage.enCours, EtapeToilettage.pret, EtapeToilettage.termine}.contains(e))
            action(ctx, Icons.description_outlined, 'Fiche technique de la prestation', () => _go(ToilettageSeancePage(
                animalId: r['animal_id'].toString(), animalNom: _nomAnimal(r), rdv: {...r, '_prestation': _prestation(r)}))),
          action(ctx, Icons.folder_open_outlined, 'Dossier de la séance (compte rendu, contrat, facture)', () async {
            await showDossierToilettage(context, r, nomClient: _nomClient(r), prestation: _prestation(r), animal: _nomAnimal(r));
            if (mounted) _charger();
          }),
          if (r['animal_id'] != null)
            action(ctx, Icons.assignment_outlined, 'Fiche animal et consignes', () => _go(ToilettageFicheClientPage(
                animalId: r['animal_id'].toString(), animalNom: _nomAnimal(r), rdvId: r['id'].toString()))),
          if ((r['client_uid']?.toString() ?? '').isNotEmpty)
            action(ctx, Icons.chat_bubble_outline, 'Contacter le propriétaire', () => _message(r)),
          action(ctx, Icons.event_note_outlined, "Voir le rendez-vous dans l'agenda",
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
    final duJour = _duJour;
    final enCours = duJour.where((r) => etapeToilettage(r) == EtapeToilettage.enCours).length;
    final prets = _rdvs.where((r) => etapeToilettage(r) == EtapeToilettage.pret).toList();
    return LayoutBuilder(builder: (context, c) {
      final large = c.maxWidth >= 860;
      final planning = DashCarte(key: _planningKey, child: _planningSection(duJour));
      final colonne = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _alertesSection(duJour, prets),
        _equipeSection(duJour),
      ]);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GridView.count(
          crossAxisCount: large ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12, mainAxisSpacing: 12,
          childAspectRatio: large ? 2.1 : 1.65,
          children: [
            DashKpi(valeur: duJour.where((r) => r['statut'] != 'absent').length, label: "Rendez-vous aujourd'hui", icon: Icons.today_outlined,
                onTap: () {
                  final ctx = _planningKey.currentContext;
                  if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
                }),
            DashKpi(valeur: enCours, label: 'Prestations en cours', icon: Icons.content_cut, teinte: _teal,
                onTap: () {
                  final ctx = _planningKey.currentContext;
                  if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
                }),
            DashKpi(valeur: prets.length, label: 'Animaux prêts', icon: Icons.pets_outlined, teinte: _vert, actif: prets.isNotEmpty,
                onTap: () { if (prets.isNotEmpty) _actions(prets.first); }),
            DashKpi(valeur: _demandes.length, label: 'Rendez-vous à confirmer', icon: Icons.mark_email_unread_outlined, teinte: _ambre,
                actif: _demandes.isNotEmpty, onTap: () => _go(const ProAgendaPage(initialTabIndex: 0))),
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
        _accesRapides(),
      ]);
    });
  }

  Widget _planningSection(List<Map<String, dynamic>> duJour) {
    final conflits = _conflits;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Planning du jour', icone: Icons.calendar_today_outlined, compteur: duJour.length,
          trailing: DashLien("Voir l'agenda", onTap: () => _go(const ProAgendaPage(initialTabIndex: 1)))),
      const SizedBox(height: 6),
      if (duJour.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 10),
            child: Text("Aucun rendez-vous aujourd'hui.", style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted))),
      for (final r in duJour)
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _actions(r),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F1EF)))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 50, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_hm(_debut(r)), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
                Text('${(r['duree_minutes'] as num?)?.toInt() ?? 60} min', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _muted)),
              ])),
              DashPhotoAnimal(url: _animaux[r['animal_id']?.toString()]?['photo_url']?.toString()),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_nomAnimal(r), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
                Text('${_prestation(r)} · ${_nomClient(r)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
                if (_employe(r) != null)
                  Text('Toiletteur : ${_employe(r)}${conflits.contains(r['id'].toString()) ? ' · conflit de planning' : ''}',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11.5,
                          color: conflits.contains(r['id'].toString()) ? _rouge : _muted)),
                if ((r['notes_client']?.toString() ?? '').trim().isNotEmpty)
                  Text(r['notes_client'].toString().trim(), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _ambre)),
              ])),
              const SizedBox(width: 6),
              Builder(builder: (_) { final st = styleEtape(etapeToilettage(r)); return DashBadge(st.label, fg: st.fg, bg: st.bg); }),
            ]),
          ),
        ),
    ]);
  }

  Widget _alertesSection(List<Map<String, dynamic>> duJour, List<Map<String, dynamic>> prets) {
    final now = DateTime.now();
    final retards = duJour.where((r) => etapeToilettage(r) == EtapeToilettage.attendu &&
        _debut(r).add(const Duration(minutes: 15)).isBefore(now)).toList();
    final aFinaliser = _rdvs.where((r) => !_memeJour(_debut(r), now) &&
        const {EtapeToilettage.arrive, EtapeToilettage.enCours, EtapeToilettage.pret, EtapeToilettage.attendu}.contains(etapeToilettage(r))).toList();
    final alertes = <(IconData, String, VoidCallback, Color)>[
      if (_demandes.isNotEmpty)
        (Icons.mark_email_unread_outlined, '${_demandes.length} rendez-vous en attente de confirmation',
            () => _go(const ProAgendaPage(initialTabIndex: 0)), _ambre),
      for (final r in prets) (Icons.pets_outlined, '${_nomAnimal(r)} est prêt à récupérer', () => _actions(r), _vert),
      for (final r in retards) (Icons.schedule, '${_nomAnimal(r)} attendu à ${_hm(_debut(r))}, pas encore arrivé', () => _actions(r), _rouge),
      if (_conflits.isNotEmpty) (Icons.warning_amber_rounded, 'Conflit de planning : un employé a deux rendez-vous en même temps',
          () => _go(const ToilettagePlanningEmployesPage()), _rouge),
      for (final r in aFinaliser) (Icons.task_alt, 'Prestation du ${_jm(_debut(r))} à finaliser — ${_nomAnimal(r)}', () => _actions(r), _ambre),
    ];
    if (alertes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DashTitre('À traiter', icone: Icons.notifications_none, compteur: alertes.length),
        const SizedBox(height: 4),
        for (final a in alertes.take(6))
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

  Widget _equipeSection(List<Map<String, dynamic>> duJour) {
    if (_employes.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final lignes = [
      for (final e in _employes.entries)
        () {
          final rdvs = duJour.where((r) => r['employe_id']?.toString() == e.key && r['statut'] != 'absent').toList();
          final enCours = rdvs.where((r) => etapeToilettage(r) == EtapeToilettage.enCours).firstOrNull;
          final prochain = rdvs.where((r) => _debut(r).isAfter(now)).firstOrNull;
          final libre = rdvs.where((r) => _fin(r).isAfter(now)).map(_fin).fold<DateTime?>(null, (m, d) => m == null || d.isAfter(m) ? d : m);
          return (nom: e.value, n: rdvs.length, enCours: enCours, prochain: prochain, libre: libre);
        }(),
    ]..sort((a, b) => b.n.compareTo(a.n));
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Équipe du jour', icone: Icons.groups_outlined, compteur: lignes.where((l) => l.n > 0).length,
          trailing: DashLien('Planning équipe', onTap: () => _go(const ToilettagePlanningEmployesPage()))),
      const SizedBox(height: 4),
      for (final l in lignes)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            CircleAvatar(radius: 14, backgroundColor: _teal.withValues(alpha: 0.1),
                child: Text(l.nom.isEmpty ? '?' : l.nom[0].toUpperCase(),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: _teal))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.nom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5, color: _ink)),
              Text(l.n == 0 ? 'Aucun rendez-vous attribué'
                  : [
                      '${l.n} rendez-vous',
                      if (l.enCours != null) 'en cours : ${_nomAnimal(l.enCours!)}'
                      else if (l.prochain != null) 'prochain à ${_hm(_debut(l.prochain!))}',
                      if (l.libre != null) 'libre à ${_hm(l.libre!)}',
                    ].join(' · '),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
            ])),
          ]),
        ),
    ]));
  }

  Widget _accesRapides() {
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
          trailing: DashLien('Statistiques', onTap: () => _go(const ToilettageDashboardPage()))),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 560 ? 4 : 2;
        return GridView.count(
          crossAxisCount: cols, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: cols == 4 ? 3.0 : 2.9,
          children: [
            tuile(Icons.add_circle_outline, 'Nouveau rendez-vous', () => _go(const ProAgendaPage(initialTabIndex: 1, nouveauRdv: true))),
            tuile(Icons.pets_outlined, 'Fiches animaux', () => _go(const ProClientsPage())),
            tuile(Icons.calendar_view_day_outlined, 'Planning équipe', () => _go(const ToilettagePlanningEmployesPage())),
            tuile(Icons.receipt_long_outlined, 'Facturation', () => _go(const FacturationPage())),
          ],
        );
      }),
    ]));
  }
}
