// Accueil pension : poste de pilotage du jour. Données réelles et modules
// EXISTANTS uniquement : séjours (pension_entrees), hébergements
// (enclos_chenil), protocoles / tâches (taches_elevage, profil_source
// 'pension'), journal (pension_updates). Mêmes briques que les autres
// tableaux de bord (widgets/dashboard/dashboard_kit.dart).
// Miroir site : website/src/components/dashboard/PensionDashboard.tsx.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/pro/animal_fiche_pension_page.dart';
import 'package:PetsMatch/pages/pro/fiches_pension_page.dart';
import 'package:PetsMatch/pages/pro/pension_entree_sortie_page.dart';
import 'package:PetsMatch/pages/pro/pension_mes_taches_page.dart';
import 'package:PetsMatch/pages/pro/pension_planning_page.dart';
import 'package:PetsMatch/pages/pro/registre_pension_page.dart';
import 'package:PetsMatch/pages/pro/pension_arrivee_depart.dart';
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:PetsMatch/utils/site_api.dart';

const _teal = kDashTeal;
const _ink = kDashInk;
const _muted = kDashMuted;
const _vert = Color(0xFF2E7D5E);
const _ambre = Color(0xFFD97706);
const _rouge = Color(0xFFB3261E);
const _violet = Color(0xFF7B5EA7);

class PensionDashboard extends StatefulWidget {
  const PensionDashboard({super.key});
  @override
  State<PensionDashboard> createState() => _PensionDashboardState();
}

class _PensionDashboardState extends State<PensionDashboard> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _sejours = [];
  List<Map<String, dynamic>> _logements = [];
  List<Map<String, dynamic>> _taches = [];
  List<Map<String, dynamic>> _incidents = [];
  // Demandes de séjour des clients (à accepter / refuser).
  List<Map<String, dynamic>> _demandes = [];
  final Map<String, Map<String, dynamic>> _animaux = {};

  @override
  void initState() {
    super.initState();
    _charger();
  }

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  DateTime? _date(dynamic v) => DateTime.tryParse(v?.toString() ?? '');
  List<Map<String, dynamic>> _liste(dynamic r) =>
      List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map)));

  Future<void> _charger() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    final now = DateTime.now();
    final jour = DateTime(now.year, now.month, now.day);
    try {
      // En pension + séjours à venir (30 j) — terminés exclus.
      _sejours = _liste(await _supa.from('pension_entrees').select()
          .eq('pro_uid', uid).eq('statut', 'en_pension')
          .lte('date_entree', _iso(jour.add(const Duration(days: 30)))).order('date_entree'))
          .where(sejourDuProfil).toList();
    } catch (_) {}
    try {
      var qd = _supa.from('pension_demandes').select().eq('pro_uid', uid).eq('statut', 'demande');
      if (User_Info.activeProfileId.isNotEmpty) qd = qd.eq('pro_profile_id', User_Info.activeProfileId);
      _demandes = _liste(await qd.order('date_arrivee'));
    } catch (_) { _demandes = []; }
    try {
      _logements = _liste(await _supa.from('enclos_chenil').select().eq('uid_eleveur', uid).order('nom'));
    } catch (_) { _logements = []; }
    try {
      final pid = User_Info.activeProfileId;
      var q = _supa.from('taches_elevage').select().eq('profil_source', 'pension').neq('statut', 'fait')
          .lte('date', _iso(jour));
      q = pid.isNotEmpty ? q.eq('eleveur_profile_id', pid) : q.eq('uid_eleveur', uid);
      _taches = _liste(await q.order('date'));
    } catch (_) { _taches = []; }
    try {
      _incidents = _liste(await _supa.from('pension_updates').select()
          .eq('pro_uid', uid).eq('incident', true)
          .gte('created_at', jour.subtract(const Duration(days: 2)).toUtc().toIso8601String()));
    } catch (_) { _incidents = []; } // colonne incident (migration_garde_compte_rendu_express.sql)
    final ids = {for (final s in _sejours) if (s['animal_id'] != null) s['animal_id'].toString()};
    try {
      if (ids.isNotEmpty) {
        final rows = await _supa.from('animaux').select('id, nom, espece, photo_url').inFilter('id', ids.toList());
        for (final a in rows as List) { _animaux[a['id'].toString()] = Map<String, dynamic>.from(a as Map); }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ── Sélections ──────────────────────────────────────────────────────────

  DateTime get _jour { final n = DateTime.now(); return DateTime(n.year, n.month, n.day); }
  bool _memeJour(DateTime? a, DateTime b) => a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  List<Map<String, dynamic>> get _presents =>
      _sejours.where((s) => !(_date(s['date_entree'])?.isAfter(_jour) ?? true)).toList();
  List<Map<String, dynamic>> get _arrivees => _sejours.where((s) => _memeJour(_date(s['date_entree']), _jour)).toList();
  List<Map<String, dynamic>> get _departs => _sejours.where((s) => _memeJour(_date(s['date_sortie_prevue']), _jour)).toList();
  List<Map<String, dynamic>> get _aConfirmer =>
      _arrivees.where((s) => s['arrivee_reelle_le'] == null).toList();
  List<Map<String, dynamic>> get _aCloturer => _sejours.where((s) {
        final d = _date(s['date_sortie_prevue']);
        return d != null && d.isBefore(_jour);
      }).toList();

  String _nom(Map<String, dynamic> s) =>
      (_animaux[s['animal_id']?.toString()]?['nom'] ?? s['animal_nom'] ?? 'Animal').toString();
  String? _photo(Map<String, dynamic> s) => _animaux[s['animal_id']?.toString()]?['photo_url']?.toString();
  String _logement(Map<String, dynamic> s) {
    final l = _logements.where((x) => x['id'].toString() == s['logement_id']?.toString()).firstOrNull;
    return l == null ? 'Sans hébergement attribué' : l['nom'].toString();
  }
  String _jm(dynamic v) { final d = _date(v); return d == null ? '' : DateFormat('dd/MM').format(d); }

  /// Capacité : somme des capacités des hébergements (1 par défaut).
  int get _capacite => _logements.fold(0, (t, l) => t + ((l['capacite'] as num?)?.toInt() ?? 1));
  Set<String> get _logementsOccupes =>
      {for (final s in _presents) if (s['logement_id'] != null) s['logement_id'].toString()};
  Set<String> get _logementsReserves => {
        for (final s in _sejours)
          if (s['logement_id'] != null && (_date(s['date_entree'])?.isAfter(_jour) ?? false)) s['logement_id'].toString(),
      }.difference(_logementsOccupes);

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _go(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _charger();
  }

  void _fiche(Map<String, dynamic> s) {
    final id = s['animal_id']?.toString();
    if (id == null || id.isEmpty) { _go(const RegistrePensionPage()); return; }
    _go(AnimalFichePensionPage(animalId: id, animalNom: _nom(s)));
  }

  Future<void> _arrivee(Map<String, dynamic> s) async {
    if (await confirmerArriveePension(context, s)) _charger();
  }

  Future<void> _depart(Map<String, dynamic> s) async {
    if (await enregistrerDepartPension(context, s)) _charger();
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator(color: _teal)));
    }
    final presents = _presents;
    final cap = _capacite;
    return LayoutBuilder(builder: (context, c) {
      final large = c.maxWidth >= 860;
      final gauche = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _demandesSection(),
        _alertesSection(),
        _entreesSortiesSection(),
        const SizedBox(height: 16),
        _presentsSection(presents),
      ]);
      final droite = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _tachesSection(),
        const SizedBox(height: 16),
        _occupationSection(presents),
      ]);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GridView.count(
          crossAxisCount: large ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12, mainAxisSpacing: 12,
          childAspectRatio: large ? 2.1 : 1.65,
          children: [
            DashKpi(valeur: presents.length, label: 'Animaux présents', icon: Icons.pets_outlined,
                onTap: () => _go(const FichesPensionPage())),
            DashKpi(valeur: _arrivees.length, label: "Arrivées aujourd'hui", icon: Icons.login_rounded, teinte: _vert,
                actif: _aConfirmer.isNotEmpty, onTap: () => _go(const PensionEntreeSortiePage())),
            DashKpi(valeur: _departs.length, label: "Départs aujourd'hui", icon: Icons.logout_rounded, teinte: _violet,
                onTap: () => _go(const PensionEntreeSortiePage())),
            // Occupation : hébergements configurés, sinon animaux présents seuls (pension familiale).
            DashKpi(valeur: _logements.isEmpty ? presents.length : _logementsOccupes.length,
                label: _logements.isEmpty ? 'Occupation (sans box)' : 'Occupés / ${_logements.length} hébergements',
                icon: Icons.home_work_outlined, teinte: _ambre, onTap: () => _go(const PensionPlanningPage())),
          ],
        ),
        if (_logements.isNotEmpty && cap > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${presents.length} animal${presents.length > 1 ? 'aux' : ''} pour une capacité de $cap place${cap > 1 ? 's' : ''}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
          ),
        const SizedBox(height: 16),
        if (large)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: gauche),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: droite),
          ])
        else ...[
          gauche,
          const SizedBox(height: 16),
          droite,
        ],
        const SizedBox(height: 16),
        _accesRapides(),
      ]);
    });
  }

  // Alertes ---------------------------------------------------------------

  // Demandes de séjour ------------------------------------------------------
  Future<void> _decider(Map<String, dynamic> d, bool accepter, {bool forcer = false}) async {
    String? motif;
    if (!accepter) {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Refuser la demande', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(
            hintText: 'Motif pour le client (facultatif) : complet à ces dates…', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Refuser')),
        ],
      ));
      if (ok != true) return;
      motif = ctrl.text.trim();
    }
    try {
      final r = await http.post(Uri.parse('$kSiteBaseUrl/api/pension/sejour'), headers: await siteApiHeaders(),
          body: jsonEncode({'action': 'decider', 'demandeId': d['id'], 'accepter': accepter, if (motif != null) 'motif': motif, if (forcer) 'forcer': true}));
      if (!mounted) return;
      // Hébergements pleins sur une partie du séjour : accepter quand même ?
      if (r.statusCode == 409 && accepter && !forcer) {
        Map j = {};
        try { j = jsonDecode(r.body) as Map; } catch (_) {}
        if (j['complet'] == true) {
          final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
            title: const Text('Pension complète', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            content: Text('${j['error']}\nAccepter quand même ce séjour ?', style: const TextStyle(fontFamily: 'Galey')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Accepter quand même')),
            ],
          ));
          if (ok == true) await _decider(d, true, forcer: true);
          return;
        }
      }
      if (r.statusCode != 200) {
        String m = 'Action impossible';
        try { m = (jsonDecode(r.body) as Map)['error']?.toString() ?? m; } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(accepter
          ? 'Séjour accepté : il est au planning et le client est prévenu' : 'Demande refusée, le client est prévenu')));
      setState(() => _loading = true);
      _charger();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Widget _demandesSection() {
    if (_demandes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DashTitre('Demandes de séjour', icone: Icons.mark_email_unread_outlined, compteur: _demandes.length),
        for (final d in _demandes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d['animal_nom'] ?? 'Animal'}${d['nouveau_pensionnaire'] == true ? ' · nouveau pensionnaire' : d['nouveau_pensionnaire'] == false ? ' · déjà venu (selon le client)' : ''}',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
              Text('Du ${_jm(d['date_arrivee'])} au ${_jm(d['date_depart'])}'
                  '${d['essai_date'] != null ? ' · essai le ${_jm(d['essai_date'])}' : ''}'
                  '${d['hebergement'] == 'box' ? ' · box' : d['hebergement'] == 'pre' ? ' · pré' : ''}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)),
              if ((d['message']?.toString() ?? '').isNotEmpty)
                Text('« ${d['message']} »', style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _muted)),
              Row(children: [
                FilledButton(onPressed: () => _decider(d, true), style: FilledButton.styleFrom(backgroundColor: _vert, visualDensity: VisualDensity.compact),
                    child: const Text('Accepter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600))),
                const SizedBox(width: 8),
                TextButton(onPressed: () => _decider(d, false), child: const Text('Refuser', style: TextStyle(fontFamily: 'Galey'))),
                const Spacer(),
                TextButton(onPressed: () => _go(AnimalFichePensionPage(animalId: d['animal_id'].toString(), animalNom: d['animal_nom']?.toString() ?? 'Animal')),
                    child: const Text('Fiche', style: TextStyle(fontFamily: 'Galey'))),
              ]),
            ]),
          ),
      ])),
    );
  }

  Widget _alertesSection() {
    final retard = _taches.where((t) => (_date(t['date'])?.isBefore(_jour) ?? false)).toList();
    final alertes = <(IconData, String, VoidCallback)>[
      for (final s in _aCloturer)
        (Icons.logout_rounded, 'Départ prévu le ${_jm(s['date_sortie_prevue'])} non clôturé — ${_nom(s)}', () => _depart(s)),
      if (retard.isNotEmpty)
        (Icons.task_alt, '${retard.length} tâche${retard.length > 1 ? 's' : ''} en retard (soins, traitements…)',
            () => _go(const PensionMesTachesPage())),
      for (final u in _incidents)
        (Icons.report_outlined, 'Incident signalé${(u['note']?.toString() ?? '').isNotEmpty ? ' : ${u['note']}' : ''}',
            () => _go(const FichesPensionPage())),
    ];
    if (alertes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DashTitre('À traiter', icone: Icons.warning_amber_rounded, compteur: alertes.length),
        const SizedBox(height: 4),
        for (final a in alertes.take(5))
          InkWell(
            onTap: a.$3,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                Icon(a.$1, size: 18, color: _rouge),
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

  // Arrivées et départs ---------------------------------------------------

  Widget _entreesSortiesSection() {
    Widget ligne(Map<String, dynamic> s, bool arrivee) {
      final fait = arrivee ? s['arrivee_reelle_le'] != null : false;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(arrivee ? Icons.login_rounded : Icons.logout_rounded, size: 18, color: arrivee ? _vert : _violet),
          const SizedBox(width: 8),
          DashPhotoAnimal(url: _photo(s), taille: 32),
          const SizedBox(width: 10),
          Expanded(child: InkWell(
            onTap: () => _fiche(s),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_nom(s), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5, color: _ink)),
              Text([
                (s['proprietaire_nom']?.toString() ?? '').trim(),
                _logement(s),
                if (fait) 'arrivé à ${hmFr(DateTime.parse(s['arrivee_reelle_le'].toString()).toLocal())}',
              ].where((x) => x.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
            ]),
          )),
          if (arrivee && fait)
            const DashBadge('Arrivé', fg: _vert, bg: Color(0xFFE7F3EC))
          else
            TextButton(
              onPressed: () => arrivee ? _arrivee(s) : _depart(s),
              child: Text(arrivee ? 'Enregistrer l\'arrivée' : 'Enregistrer le départ',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ]),
      );
    }
    final arr = _arrivees, dep = _departs;
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Arrivées et départs du jour', icone: Icons.swap_horiz_rounded, compteur: arr.length + dep.length,
          trailing: DashLien('Entrées / sorties', onTap: () => _go(const PensionEntreeSortiePage()))),
      const SizedBox(height: 4),
      if (arr.isEmpty && dep.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 8),
            child: Text("Aucune arrivée ni aucun départ prévu aujourd'hui.", style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted))),
      for (final s in arr) ligne(s, true),
      for (final s in dep) ligne(s, false),
    ]));
  }

  // Animaux présents ------------------------------------------------------

  Widget _presentsSection(List<Map<String, dynamic>> presents) {
    final tri = [...presents]..sort((a, b) =>
        (_date(a['date_sortie_prevue']) ?? DateTime(2100)).compareTo(_date(b['date_sortie_prevue']) ?? DateTime(2100)));
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Animaux présents', icone: Icons.pets_outlined, compteur: tri.length,
          trailing: DashLien('Tous', onTap: () => _go(const FichesPensionPage()))),
      const SizedBox(height: 4),
      if (tri.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Aucun animal en pension.', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted))),
      for (final s in tri.take(8))
        InkWell(
          onTap: () => _fiche(s),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              DashPhotoAnimal(url: _photo(s), taille: 36),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_nom(s), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5, color: _ink)),
                Text('${_logement(s)}${_jm(s['date_sortie_prevue']).isNotEmpty ? ' · départ le ${_jm(s['date_sortie_prevue'])}' : ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
                if ((s['consignes_sejour']?.toString() ?? '').trim().isNotEmpty)
                  Text(s['consignes_sejour'].toString().split('\n').first, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _ambre, fontWeight: FontWeight.w600)),
              ])),
              Builder(builder: (_) {
                final n = _taches.where((t) => t['animal_id']?.toString() == s['animal_id']?.toString()).length;
                return n == 0 ? const SizedBox.shrink() : DashBadge('$n tâche${n > 1 ? 's' : ''}', fg: _ambre, bg: const Color(0xFFFFF4DC));
              }),
            ]),
          ),
        ),
    ]));
  }

  // Tâches et soins -------------------------------------------------------

  Widget _tachesSection() {
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Tâches et soins à faire', icone: Icons.checklist_rtl_outlined, compteur: _taches.length,
          trailing: DashLien('Mes tâches', onTap: () => _go(const PensionMesTachesPage()))),
      const SizedBox(height: 4),
      if (_taches.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 8),
            child: Text("Rien à faire pour l'instant.", style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted))),
      for (final t in _taches.take(8))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(Icons.radio_button_unchecked, size: 18,
                color: (_date(t['date'])?.isBefore(_jour) ?? false) ? _rouge : _muted),
            const SizedBox(width: 10),
            Expanded(child: Text(
              [(t['titre'] ?? 'Tâche').toString(), if ((t['animal_nom']?.toString() ?? '').isNotEmpty) t['animal_nom'].toString()].join(' · '),
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _ink))),
            if (_date(t['date'])?.isBefore(_jour) ?? false)
              Text('depuis le ${_jm(t['date'])}', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _rouge)),
          ]),
        ),
    ]));
  }

  // Occupation ------------------------------------------------------------

  Widget _occupationSection(List<Map<String, dynamic>> presents) {
    final occ = _logementsOccupes, res = _logementsReserves;
    final dispo = _logements.length - occ.length - res.length;
    Widget chiffre(String label, int v, Color c) => Expanded(child: Column(children: [
          Text('$v', style: TextStyle(fontFamily: 'Galey', fontSize: 22, fontWeight: FontWeight.w700, color: c)),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
        ]));
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Occupation des hébergements', icone: Icons.home_work_outlined,
          trailing: DashLien('Planning', onTap: () => _go(const PensionPlanningPage()))),
      const SizedBox(height: 10),
      if (_logements.isEmpty)
        Text('Pension sans box individuel : ${presents.length} animal${presents.length > 1 ? 'aux' : ''} présent${presents.length > 1 ? 's' : ''}.',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted))
      else
        Row(children: [
          chiffre('Disponibles', dispo < 0 ? 0 : dispo, _vert),
          chiffre('Occupés', occ.length, _teal),
          chiffre('Réservés', res.length, _ambre),
        ]),
    ]));
  }

  // Accès rapides ---------------------------------------------------------

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
      const DashTitre('Accès rapides', icone: Icons.bolt_outlined),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 560 ? 4 : 2;
        return GridView.count(
          crossAxisCount: cols, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: cols == 4 ? 3.0 : 2.9,
          children: [
            tuile(Icons.add_circle_outline, 'Nouvelle réservation', () => _go(const RegistrePensionPage())),
            tuile(Icons.calendar_view_week_outlined, 'Planning des hébergements', () => _go(const PensionPlanningPage())),
            tuile(Icons.swap_horiz_rounded, 'Entrées / sorties', () => _go(const PensionEntreeSortiePage())),
            tuile(Icons.pets_outlined, 'Animaux présents', () => _go(const FichesPensionPage())),
          ],
        );
      }),
    ]));
  }
}
