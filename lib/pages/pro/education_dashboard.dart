// Accueil éducateur / comportementaliste : tableau de bord de l'activité.
// Données réelles et modules EXISTANTS uniquement : agenda (rdv), cours
// collectifs, objectifs (education_objectifs), comptes rendus de séance
// (education_progression), forfaits souscrits. Mêmes briques que les tableaux
// véto / ostéo / pet-sitter (widgets/dashboard/dashboard_kit.dart).
// Miroir site : website/src/components/dashboard/EducationDashboard.tsx.
// Scopé au profil actif (pro_profile_id) — jamais l'uid seul pour l'agenda.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/itineraire.dart';
import 'package:PetsMatch/utils/rdv_animaux.dart' show animauxDetailRdv, choisirAnimalRdv;
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/pro/pro_clients_page.dart';
import 'package:PetsMatch/pages/pro/education_bibliotheque_page.dart';
import 'package:PetsMatch/pages/pro/education_suivi_page.dart';
import 'package:PetsMatch/pages/pro/education_shared.dart';
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';

const _teal = kDashTeal;
const _ink = kDashInk;
const _muted = kDashMuted;
const _vert = Color(0xFF2E7D5E);
const _ambre = Color(0xFFD97706);

class EducationDashboard extends StatefulWidget {
  const EducationDashboard({super.key});
  @override
  State<EducationDashboard> createState() => _EducationDashboardState();
}

class _EducationDashboardState extends State<EducationDashboard> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _rdvs = [];
  List<Map<String, dynamic>> _cours = [];
  List<Map<String, dynamic>> _objectifs = [];
  List<Map<String, dynamic>> _seances = [];
  List<Map<String, dynamic>> _forfaits = [];
  /// Demandes à traiter : RDV (statut « demande ») et inscriptions aux cours collectifs.
  int _demandesRdv = 0;
  int _demandesCours = 0;
  /// Animaux de « Mes animaux suivis » (même source que ProClientsPage :
  /// accès accordés à ce profil + animaux vus en RDV avec ce profil).
  Set<String> _animauxSuivis = {};
  final Map<String, String> _clients = {};
  final Map<String, Map<String, dynamic>> _animaux = {};
  final _planningKey = GlobalKey();
  final _crKey = GlobalKey();

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

  List<Map<String, dynamic>> _liste(dynamic rows) =>
      List<Map<String, dynamic>>.from((rows as List).map((e) => Map<String, dynamic>.from(e as Map)));

  Future<void> _charger() async {
    final pid = _pid;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (pid.isEmpty || uid == null) { setState(() => _loading = false); return; }
    final now = DateTime.now();
    final jour = DateTime(now.year, now.month, now.day);
    try {
      _rdvs = _liste(await _supa.from('rdv').select()
          .eq('pro_profile_id', pid).inFilter('statut', ['confirme', 'termine'])
          .gte('date_heure', jour.subtract(const Duration(days: 60)).toUtc().toIso8601String())
          .lte('date_heure', jour.add(const Duration(days: 31)).toUtc().toIso8601String())
          .order('date_heure'));
    } catch (_) {}
    try {
      _cours = _liste(await _supa.from('cours_collectifs').select()
          .eq('pro_uid', uid).neq('statut', 'annule')
          .gte('date_heure', jour.toUtc().toIso8601String())
          .lt('date_heure', jour.add(const Duration(days: 1)).toUtc().toIso8601String())
          .order('date_heure'));
      _cours = _cours.where((c) => c['pro_profile_id'] == null || c['pro_profile_id'].toString() == pid).toList();
    } catch (_) { _cours = []; }
    try {
      _objectifs = _liste(await _supa.from('education_objectifs').select()
          .eq('pro_uid', uid).order('ordre'));
      _objectifs = _objectifs.where((o) => o['pro_profile_id'] == null || o['pro_profile_id'].toString() == pid).toList();
    } catch (_) { _objectifs = []; }
    try {
      _seances = _liste(await _supa.from('education_progression').select()
          .eq('pro_uid', uid).order('date_seance', ascending: false).limit(300));
      _seances = _seances.where((x) => x['pro_profile_id'] == null || x['pro_profile_id'].toString() == pid).toList();
    } catch (_) { _seances = []; }
    try {
      _forfaits = _liste(await _supa.from('forfaits_souscrits').select().eq('pro_uid', uid).eq('statut', 'actif'));
      // Forfaits d'un autre profil pro du même compte : jamais ici.
      _forfaits = _forfaits.where((f) => f['pro_profile_id'] == null || f['pro_profile_id'].toString() == pid).toList();
    } catch (_) { _forfaits = []; }
    try {
      final r = await Future.wait([
        _supa.from('animal_access').select('animal_id').eq('pro_profile_id', pid)
            .inFilter('statut', ['active', 'write_requested', 'active_write']),
        _supa.from('rdv').select('animal_id').eq('pro_uid', uid).eq('pro_profile_id', pid)
            .inFilter('statut', ['confirme', 'termine']),
      ]);
      _animauxSuivis = {
        for (final l in r) for (final x in (l as List)) if (x['animal_id'] != null) x['animal_id'].toString(),
      };
    } catch (_) { _animauxSuivis = {}; }
    try {
      _demandesRdv = (await _supa.from('rdv').select('id').eq('pro_profile_id', pid).inFilter('statut', ['demande', 'contre_proposition']) as List).length;
      _demandesCours = (await _supa.from('cours_collectifs_participants').select('id, cours_collectifs!inner(pro_uid)')
          .eq('statut', 'demande').eq('cours_collectifs.pro_uid', uid) as List).length;
    } catch (_) {}
    await _chargerNoms();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _chargerNoms() async {
    final profils = {for (final r in _rdvs) if (r['client_profile_id'] != null) r['client_profile_id'].toString()};
    final animaux = {
      for (final r in _rdvs) if (r['animal_id'] != null) r['animal_id'].toString(),
      for (final id in _suivisIds) id,
    };
    try {
      if (profils.isNotEmpty) {
        final rows = await _supa.from('user_profiles_complet')
            .select('id, firstname, lastname, nom, profile_type').inFilter('id', profils.toList());
        for (final p in rows as List) {
          final perso = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
          final structure = (p['nom']?.toString() ?? '').trim();
          _clients[p['id'].toString()] =
              p['profile_type'] != 'particulier' && structure.isNotEmpty ? structure : (perso.isNotEmpty ? perso : structure);
        }
      }
    } catch (_) {}
    try {
      if (animaux.isNotEmpty) {
        final rows = await _supa.from('animaux').select('id, nom, espece, photo_url').inFilter('id', animaux.toList());
        for (final a in rows as List) { _animaux[a['id'].toString()] = Map<String, dynamic>.from(a as Map); }
      }
    } catch (_) {}
  }

  // ── Sélections ──────────────────────────────────────────────────────────

  DateTime _debut(Map<String, dynamic> r) => DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal() ?? DateTime(2000);
  bool _memeJour(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  bool _domicile(Map<String, dynamic> r) => (r['lieu']?.toString().trim() ?? '').isNotEmpty || r['lieu_lat'] != null;
  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _jm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  /// Animaux suivis : un objectif non acquis ou un forfait actif.
  Set<String> get _suivisIds => {
        for (final o in _objectifs) if (o['statut'] != 'acquis' && o['animal_id'] != null) o['animal_id'].toString(),
        for (final f in _forfaits) if (f['animal_id'] != null) f['animal_id'].toString(),
      };

  List<Map<String, dynamic>> _duJour(DateTime j) =>
      _rdvs.where((r) => _memeJour(_debut(r), j)).toList()..sort((a, b) => _debut(a).compareTo(_debut(b)));

  /// Séances terminées sans compte rendu (rdv_id) + brouillons.
  List<Map<String, dynamic>> get _aFinaliser {
    final avecCr = {for (final s in _seances) if (s['rdv_id'] != null && s['statut'] != 'brouillon') s['rdv_id'].toString()};
    final brouillons = {for (final s in _seances) if (s['rdv_id'] != null && s['statut'] == 'brouillon') s['rdv_id'].toString()};
    final now = DateTime.now();
    return [
      for (final r in _rdvs)
        if (r['animal_id'] != null &&
            (r['statut'] == 'termine' || _debut(r).isBefore(now.subtract(const Duration(hours: 1)))) &&
            !avecCr.contains(r['id'].toString()))
          {...r, '_brouillon': brouillons.contains(r['id'].toString())},
      for (final s in _seances)
        if (s['statut'] == 'brouillon' && s['rdv_id'] == null) {...s, '_seule': true},
    ];
  }

  List<Map<String, dynamic>> _deplacements(DateTime jour) => _rdvs.where((r) =>
      r['statut'] == 'confirme' && _domicile(r) &&
      !_debut(r).isBefore(jour) && _debut(r).isBefore(jour.add(const Duration(days: 7)))).toList();

  String _nomClient(Map<String, dynamic> r) {
    final n = _clients[r['client_profile_id']?.toString() ?? ''];
    if (n != null && n.isNotEmpty) return n;
    final m = r['client_nom_manuel']?.toString() ?? '';
    return m.isNotEmpty ? m : 'Client';
  }

  String _nomAnimal(Map<String, dynamic> r) {
    // Plusieurs animaux sur la séance : tous les noms.
    final detail = animauxDetailRdv(r);
    if (detail.isNotEmpty) return detail.map((a) => a['nom']?.toString() ?? '').where((n) => n.isNotEmpty).join(' + ');
    final n = _animaux[r['animal_id']?.toString()]?['nom']?.toString() ?? '';
    if (n.isNotEmpty) return n;
    final m = r['animal_nom_manuel']?.toString() ?? '';
    return m.isNotEmpty ? m : 'Animal';
  }

  ({String label, Color fg, Color bg}) _statut(Map<String, dynamic> r, DateTime now) {
    if (r['statut'] == 'termine') return (label: 'Terminée', fg: const Color(0xFF4B5563), bg: const Color(0xFFF1F2F4));
    final fin = _debut(r).add(Duration(minutes: (r['duree_minutes'] as num?)?.toInt() ?? 60));
    if (fin.isBefore(now)) return (label: 'À clôturer', fg: _ambre, bg: const Color(0xFFFFF4DC));
    if (_debut(r).isBefore(now)) return (label: 'En cours', fg: _teal, bg: const Color(0xFFE6F2F3));
    return (label: 'À venir', fg: const Color(0xFF1D4ED8), bg: const Color(0xFFE8F0FE));
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _go(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _charger();
  }

  /// Plusieurs animaux sur la séance : l'animal choisi ({id, nom}), sinon celui du RDV.
  Future<Map<String, dynamic>?> _animalSeance(Map<String, dynamic> r, {String? table, String titre = 'Fiche de quel animal ?'}) async {
    if (animauxDetailRdv(r).isNotEmpty) return choisirAnimalRdv(context, r, table: table, color: _teal, titre: titre);
    final id = r['animal_id']?.toString();
    return id == null ? null : {'id': id, 'nom': _nomAnimal(r)};
  }

  Future<void> _fiche(Map<String, dynamic> r, {int onglet = 0, bool compteRendu = false}) async {
    final a = await _animalSeance(r, table: compteRendu ? 'education_progression' : null,
        titre: compteRendu ? 'Compte rendu de quel animal ?' : 'Fiche de quel animal ?');
    if (a == null || !mounted) return;
    _go(EducationSuiviPage(
      animalId: a['id'].toString(),
      animalNom: a['nom']?.toString() ?? _nomAnimal(r),
      ownerProfileId: r['client_profile_id']?.toString(),
      rdvId: compteRendu ? r['id']?.toString() : null,
      initialTab: compteRendu ? 2 : onglet,
    ));
  }

  Future<void> _actions(Map<String, dynamic> r) async {
    final now = DateTime.now();
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
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
              DashBadge(_statut(r, now).label, fg: _statut(r, now).fg, bg: _statut(r, now).bg),
            ]),
            if ((r['motif']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(r['motif'].toString(), style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: _ink)),
            ],
            if (_domicile(r)) ...[
              const SizedBox(height: 4),
              Text(r['lieu']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)),
            ],
            const SizedBox(height: 8),
            if (r['animal_id'] != null)
              _action(ctx, Icons.folder_open_outlined, 'Dossier de la séance', () async {
                final a = await _animalSeance(r, table: 'education_progression', titre: 'Dossier de quel animal ?');
                if (a == null || !mounted) return;
                _go(EducationSuiviPage(
                  animalId: a['id'].toString(), animalNom: a['nom']?.toString() ?? _nomAnimal(r), ownerProfileId: r['client_profile_id']?.toString(),
                  ownerName: _nomClient(r), rdvId: r['id']?.toString(), dossier: true));
              }),
            _action(ctx, Icons.assignment_ind_outlined, 'Ouvrir la fiche éducative', () => _fiche(r)),
            _action(ctx, Icons.track_changes_outlined, 'Consulter les objectifs', () => _fiche(r, onglet: 1)),
            if (_domicile(r))
              _action(ctx, Icons.directions_outlined, "Ouvrir l'itinéraire", () => ouvrirItineraire(context,
                  lat: (r['lieu_lat'] as num?)?.toDouble(), lng: (r['lieu_lng'] as num?)?.toDouble(), adresse: r['lieu']?.toString())),
            _action(ctx, Icons.edit_note_outlined, 'Rédiger le compte rendu', () => _fiche(r, compteRendu: true)),
            _action(ctx, Icons.event_note_outlined, "Voir la séance dans l'agenda",
                () => _go(ProAgendaPage(initialTabIndex: 1, focusRdvId: r['id']?.toString()))),
          ]),
        ),
      ),
    );
  }

  Widget _action(BuildContext ctx, IconData ic, String t, VoidCallback onTap) => ListTile(
        contentPadding: EdgeInsets.zero, dense: true,
        leading: Icon(ic, color: _teal),
        title: Text(t, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
        onTap: () { Navigator.pop(ctx); onTap(); },
      );

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator(color: _teal)));
    }
    final now = DateTime.now();
    final jour = DateTime(now.year, now.month, now.day);
    final duJour = _duJour(jour);
    final aFinaliser = _aFinaliser;
    final deplacements = _deplacements(jour);
    final suivis = _suivisIds;
    return LayoutBuilder(builder: (context, c) {
      final large = c.maxWidth >= 860;
      final planning = DashCarte(key: _planningKey, child: _planningSection(duJour, now));
      final colonne = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _suivisSection(suivis, now),
        const SizedBox(height: 16),
        _crSection(aFinaliser),
        if (deplacements.isNotEmpty) ...[
          const SizedBox(height: 16),
          _deplacementsSection(deplacements),
        ],
      ]);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (n, texte, page) in [
          (_demandesRdv, 'demande${_demandesRdv > 1 ? 's' : ''} de rendez-vous à traiter', const ProAgendaPage(initialTabIndex: 0) as Widget),
          (_demandesCours, "demande${_demandesCours > 1 ? 's' : ''} d'inscription à un cours collectif", const ProAgendaPage(ongletAgenda: true) as Widget),
        ])
          if (n > 0) Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: const Color(0xFFFFF4DC), borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _go(page),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    const Icon(Icons.mark_email_unread_outlined, color: _ambre),
                    const SizedBox(width: 10),
                    Expanded(child: Text('$n $texte', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _ink))),
                    const Icon(Icons.chevron_right, color: _muted),
                  ]),
                ),
              ),
            ),
          ),
        GridView.count(
          crossAxisCount: large ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12, mainAxisSpacing: 12,
          childAspectRatio: large ? 2.1 : 1.65,
          children: [
            DashKpi(valeur: duJour.length + _cours.length, label: "Rendez-vous aujourd'hui", icon: Icons.today_outlined,
                onTap: () {
                  final ctx = _planningKey.currentContext;
                  if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
                }),
            // Même décompte que la page ouverte (avant : seulement les animaux
            // avec un objectif en cours / un forfait → 0 alors que la liste en montrait 2).
            DashKpi(valeur: _animauxSuivis.length, label: 'Animaux suivis', icon: Icons.pets_outlined, teinte: _vert,
                onTap: () => _go(const ProClientsPage())),
            DashKpi(valeur: deplacements.length, label: 'À domicile (7 jours)', icon: Icons.home_work_outlined,
                teinte: const Color(0xFF7B5EA7), onTap: () => _go(const ProAgendaPage(initialTabIndex: 1))),
            DashKpi(valeur: aFinaliser.length, label: 'Comptes rendus à finaliser', icon: Icons.edit_note_outlined, teinte: _ambre,
                actif: aFinaliser.isNotEmpty,
                onTap: () {
                  final ctx = _crKey.currentContext;
                  if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
                }),
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
        _accesRapides(aFinaliser),
      ]);
    });
  }

  // Planning du jour ------------------------------------------------------

  Widget _planningSection(List<Map<String, dynamic>> duJour, DateTime now) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Planning du jour', icone: Icons.calendar_today_outlined, compteur: duJour.length + _cours.length,
          trailing: DashLien("Voir l'agenda", onTap: () => _go(const ProAgendaPage(initialTabIndex: 1)))),
      const SizedBox(height: 6),
      if (duJour.isEmpty && _cours.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 10),
            child: Text("Aucune séance prévue aujourd'hui.", style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted))),
      for (final r in duJour) _ligne(r, now),
      for (final c in _cours)
        InkWell(
          onTap: () => _go(const ProAgendaPage(ongletAgenda: true)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(children: [
              SizedBox(width: 50, child: Text(_hm(_debut(c)),
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink))),
              const Icon(Icons.groups_outlined, color: _teal, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c['titre']?.toString() ?? 'Cours collectif',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
                Text(['Séance collective', if ((c['lieu']?.toString() ?? '').isNotEmpty) c['lieu'].toString()].join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
              ])),
            ]),
          ),
        ),
    ]);
  }

  Widget _ligne(Map<String, dynamic> r, DateTime now) {
    final st = _statut(r, now);
    final duree = (r['duree_minutes'] as num?)?.toInt() ?? 60;
    final motif = (r['motif']?.toString() ?? '').trim();
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _actions(r),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F1EF)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 50,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_hm(_debut(r)), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
              Text('$duree min', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _muted)),
            ]),
          ),
          DashPhotoAnimal(url: _animaux[r['animal_id']?.toString()]?['photo_url']?.toString()),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_nomAnimal(r), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
            Text([_nomClient(r), if (motif.isNotEmpty) motif].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
            const SizedBox(height: 2),
            Row(children: [
              Icon(_domicile(r) ? Icons.place_outlined : Icons.store_mall_directory_outlined, size: 13, color: _muted),
              const SizedBox(width: 3),
              Flexible(child: Text(_domicile(r) ? r['lieu']?.toString() ?? 'À domicile' : 'Au cabinet / terrain',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted))),
            ]),
          ])),
          const SizedBox(width: 6),
          DashBadge(st.label, fg: st.fg, bg: st.bg),
        ]),
      ),
    );
  }

  // Suivis éducatifs en cours ---------------------------------------------

  Widget _suivisSection(Set<String> ids, DateTime now) {
    final lignes = [
      for (final id in ids)
        () {
          final objs = _objectifs.where((o) => o['animal_id']?.toString() == id && o['statut'] != 'acquis').toList()
            ..sort((a, b) => (b['prioritaire'] == true ? 1 : 0) - (a['prioritaire'] == true ? 1 : 0));
          final derniere = _seances.where((s) => s['animal_id']?.toString() == id && s['statut'] != 'brouillon').firstOrNull;
          final prochaine = (_rdvs.where((r) => r['animal_id']?.toString() == id && r['statut'] == 'confirme' && _debut(r).isAfter(now)).toList()
                ..sort((a, b) => _debut(a).compareTo(_debut(b))))
              .firstOrNull;
          return (id: id, objectif: objs.isEmpty ? null : objs.first, derniere: derniere, prochaine: prochaine);
        }(),
    ]..sort((a, b) {
        final pa = a.prochaine == null ? DateTime(2100) : _debut(a.prochaine!);
        final pb = b.prochaine == null ? DateTime(2100) : _debut(b.prochaine!);
        return pa.compareTo(pb);
      });
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Suivis éducatifs en cours', icone: Icons.track_changes_outlined, compteur: lignes.length,
          trailing: lignes.isEmpty ? null : DashLien('Tous', onTap: () => _go(const ProClientsPage()))),
      const SizedBox(height: 6),
      if (lignes.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Aucun suivi en cours.', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted))),
      for (final l in lignes.take(6))
        InkWell(
          onTap: () => _go(EducationSuiviPage(animalId: l.id,
              animalNom: _animaux[l.id]?['nom']?.toString() ?? 'Animal')),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              DashPhotoAnimal(url: _animaux[l.id]?['photo_url']?.toString(), taille: 34),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_animaux[l.id]?['nom']?.toString() ?? 'Animal',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5, color: _ink)),
                Text(l.objectif == null ? 'Forfait en cours'
                    : '${l.objectif!['libelle']} · ${kEduObjectifStatutLabels[l.objectif!['statut']] ?? ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
                Text([
                  if (l.derniere != null) 'Dernière : ${_jm(DateTime.tryParse(l.derniere!['date_seance'].toString()) ?? now)}',
                  if (l.prochaine != null) 'Prochaine : ${_jm(_debut(l.prochaine!))}',
                ].join(' · '), style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
              ])),
              const Icon(Icons.chevron_right, color: _muted, size: 18),
            ]),
          ),
        ),
    ]));
  }

  // Comptes rendus à finaliser ---------------------------------------------

  Widget _crSection(List<Map<String, dynamic>> items) {
    return DashCarte(key: _crKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Comptes rendus à finaliser', icone: Icons.edit_note_outlined, compteur: items.length),
      const SizedBox(height: 6),
      if (items.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Tout est à jour.', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted))),
      for (final r in items.take(5))
        InkWell(
          onTap: () => r['_seule'] == true
              ? _go(EducationSuiviPage(animalId: r['animal_id'].toString(),
                  animalNom: _animaux[r['animal_id'].toString()]?['nom']?.toString() ?? 'Animal', initialTab: 2))
              : _fiche(r, compteRendu: true),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              const Icon(Icons.description_outlined, color: _ambre, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(
                r['_seule'] == true
                    ? '${_animaux[r['animal_id']?.toString()]?['nom'] ?? 'Animal'} · brouillon du ${r['date_seance'] ?? ''}'
                    : '${_nomAnimal(r)} · séance du ${_jm(_debut(r))}${r['_brouillon'] == true ? ' (brouillon)' : ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _ink))),
              const Text('Rédiger', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: _teal)),
            ]),
          ),
        ),
    ]));
  }

  // Mes déplacements -------------------------------------------------------

  Widget _deplacementsSection(List<Map<String, dynamic>> items) {
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Mes déplacements (7 jours)', icone: Icons.directions_car_outlined, compteur: items.length),
      const SizedBox(height: 6),
      for (final r in items.take(6))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: 74, child: Text('${_jm(_debut(r))} ${_hm(_debut(r))}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: _ink))),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_nomAnimal(r)} · ${_nomClient(r)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _ink)),
              Text(r['lieu']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
            ])),
            IconButton(
              tooltip: 'Itinéraire',
              icon: const Icon(Icons.directions_outlined, color: _teal),
              onPressed: () => ouvrirItineraire(context,
                  lat: (r['lieu_lat'] as num?)?.toDouble(), lng: (r['lieu_lng'] as num?)?.toDouble(), adresse: r['lieu']?.toString()),
            ),
          ]),
        ),
    ]));
  }

  // Accès rapides ----------------------------------------------------------

  Widget _accesRapides(List<Map<String, dynamic>> aFinaliser) {
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
      const DashTitre('Accès rapides', icone: Icons.bolt_outlined),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 560 ? 4 : 2;
        return GridView.count(
          crossAxisCount: cols, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: cols == 4 ? 3.0 : 2.9,
          children: [
            tuile(Icons.add_circle_outline, 'Nouveau rendez-vous', () => _go(const ProAgendaPage(initialTabIndex: 1, nouveauRdv: true))),
            tuile(Icons.pets_outlined, 'Mes animaux suivis', () => _go(const ProClientsPage())),
            tuile(Icons.fitness_center_outlined, "Mes programmes d'exercices", () => _go(const EducationBibliothequePage())),
            tuile(Icons.edit_note_outlined, 'Comptes rendus à finaliser', () {
              final ctx = _crKey.currentContext;
              if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
            }),
          ],
        );
      }),
    ]));
  }
}
