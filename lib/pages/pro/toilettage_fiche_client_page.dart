// Fiche toilettage d'un animal — vue métier : en-tête commun (identité,
// propriétaire, urgence, personnes autorisées), onglets Synthèse ·
// Prestations · Consignes · Historique.
// Données : rdv (prestations, étapes), prestations_toilettage (catalogue),
// fiches_toilettage (consignes PERMANENTES — une par animal × salon),
// seances_toilettage (fiche technique par prestation), fiches_toilettage_photos
// (avant / après), allergies / traitements (déclarés par le propriétaire,
// lecture seule). Miroir site : mes-patients/[id] (onglets toiletteur).
// Scopé au profil toiletteur actif (pro_profile_id) — jamais l'uid seul.
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/widgets/animal/pro_animal_entete.dart';
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart' show DashBadge;
import 'package:PetsMatch/pages/pro/toilettage_constantes.dart';
import 'package:PetsMatch/pages/pro/toilettage_salon_dashboard.dart' show etapeToilettage, styleEtape, EtapeToilettage;
import 'package:PetsMatch/pages/pro/toilettage_seance_page.dart';

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1F2A2E);
const _rouge = Color(0xFFB3261E);
const _ambre = Color(0xFFD97706);

class ToilettageFicheClientPage extends StatefulWidget {
  final String animalId;
  final String animalNom;
  /// Rendez-vous d'où l'on vient (facultatif).
  final String? rdvId;
  final int initialTab;
  const ToilettageFicheClientPage({super.key, required this.animalId, required this.animalNom, this.rdvId, this.initialTab = 0});

  @override
  State<ToilettageFicheClientPage> createState() => _ToilettageFicheClientPageState();
}

class _ToilettageFicheClientPageState extends State<ToilettageFicheClientPage> with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;
  late final TabController _tabs;
  bool _loading = true, _saving = false;
  Map<String, dynamic>? _fiche;
  List<Map<String, dynamic>> _rdvs = [];
  List<Map<String, dynamic>> _seances = [];
  List<Map<String, dynamic>> _photos = [];
  List<Map<String, dynamic>> _allergies = [];
  List<Map<String, dynamic>> _traitements = [];
  Map<String, String> _prestations = {};
  Map<String, String> _employes = {};
  String? _tolerance;

  static const _champsConsignes = [
    ('type_poil', 'Type de poil'),
    ('particularites_pelage', 'Particularités du pelage'),
    ('coupe_habituelle', 'Coupe habituelle'),
    ('longueur_coupe', 'Longueur souhaitée'),
    ('shampooing_prefere', 'Shampooing habituel'),
    ('produits_a_eviter', 'Produits à éviter'),
    ('zones_sensibles', 'Zones sensibles'),
    ('comportement_manipulation', 'Comportement pendant la manipulation'),
    ('demandes_specifiques', 'Demandes spécifiques du propriétaire'),
    ('notes', 'Notes internes'),
  ];
  final Map<String, TextEditingController> _c = {
    for (final k in _champsConsignes) k.$1: TextEditingController(),
  };

  String get _pid => User_Info.activeProfileId;
  List<Map<String, dynamic>> _l(dynamic r) =>
      List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map)));

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this, initialIndex: widget.initialTab.clamp(0, 3));
    _charger();
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in _c.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _charger() async {
    final id = widget.animalId;
    if (_pid.isEmpty) { setState(() => _loading = false); return; }
    try {
      _fiche = await _supa.from('fiches_toilettage').select().eq('pro_profile_id', _pid).eq('animal_id', id).maybeSingle();
    } catch (_) {}
    for (final k in _champsConsignes) { _c[k.$1]!.text = _fiche?[k.$1]?.toString() ?? ''; }
    _tolerance = _fiche?['tolerance_sechoir']?.toString();
    try {
      _rdvs = _l(await _supa.from('rdv').select().eq('pro_profile_id', _pid).eq('animal_id', id)
          .inFilter('statut', ['demande', 'contre_proposition', 'confirme', 'termine', 'absent'])
          .order('date_heure', ascending: false).limit(150));
    } catch (_) {}
    try {
      _seances = _l(await _supa.from('seances_toilettage').select().eq('pro_profile_id', _pid).eq('animal_id', id)
          .order('date_seance', ascending: false));
    } catch (_) { _seances = []; }
    if (_fiche != null) {
      try {
        _photos = _l(await _supa.from('fiches_toilettage_photos').select().eq('fiche_id', _fiche!['id']).order('created_at'));
      } catch (_) {}
    }
    final prIds = _rdvs.map((r) => r['prestation_id']?.toString()).whereType<String>().toSet().toList();
    if (prIds.isNotEmpty) {
      try {
        _prestations = {for (final p in await _supa.from('prestations_toilettage').select('id, nom').inFilter('id', prIds)) p['id'].toString(): p['nom'].toString()};
      } catch (_) {}
    }
    try {
      _employes = {
        for (final e in await _supa.from('employes').select('id, prenom, nom').eq('eleveur_profile_id', _pid))
          e['id'].toString(): '${e['prenom'] ?? ''} ${e['nom'] ?? ''}'.trim(),
      };
    } catch (_) {}
    try { _allergies = _l(await _supa.from('allergies').select().eq('animal_id', id)); } catch (_) {}
    try { _traitements = _l(await _supa.from('traitements').select().eq('animal_id', id).order('date', ascending: false)); } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  DateTime _debut(Map<String, dynamic> r) => DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal() ?? DateTime(2000);
  String _jour(DateTime d) => DateFormat('EEE d MMM yyyy', 'fr_FR').format(d);
  String _hm(DateTime d) => DateFormat('HH:mm').format(d);
  String _prestation(Map<String, dynamic> r) =>
      _prestations[r['prestation_id']?.toString()] ?? ((r['motif']?.toString() ?? '').trim().isEmpty ? 'Prestation' : r['motif'].toString().trim());
  Map<String, dynamic>? _seanceDe(Map<String, dynamic> r) => _seances.where((s) => s['rdv_id']?.toString() == r['id']?.toString()).firstOrNull;

  List<Map<String, dynamic>> get _aVenir {
    final now = DateTime.now();
    return _rdvs.where((r) => const {'demande', 'contre_proposition', 'confirme'}.contains(r['statut'])
        && _debut(r).add(Duration(minutes: (r['duree_minutes'] as num?)?.toInt() ?? 60)).isAfter(now)
        && etapeToilettage(r) != EtapeToilettage.pret).toList()
      ..sort((a, b) => _debut(a).compareTo(_debut(b)));
  }
  List<Map<String, dynamic>> get _passees => _rdvs.where((r) => !_aVenir.contains(r)).toList();
  List<Map<String, dynamic>> get _terminees => _rdvs.where((r) => r['statut'] == 'termine').toList();

  /// Intervalle moyen (en semaines) entre les prestations terminées.
  String? get _frequence {
    final d = _terminees.map(_debut).toList()..sort();
    if (d.length < 2) return null;
    final jours = d.last.difference(d.first).inDays / (d.length - 1);
    if (jours < 10) return null;
    return 'environ toutes les ${(jours / 7).round()} semaines';
  }

  String _allergieLabel(Map<String, dynamic> a) => (a['nom'] ?? a['allergene'] ?? a['description'] ?? '').toString();
  bool _traitementEnCours(Map<String, dynamic> t) {
    final fin = DateTime.tryParse(t['date_fin']?.toString() ?? '');
    return fin == null || fin.isAfter(DateTime.now());
  }

  Widget _carte(String titre, IconData ic, Widget child, {Widget? action}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE6E8E6))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(ic, size: 17, color: _teal),
            const SizedBox(width: 8),
            Expanded(child: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink))),
            if (action != null) action,
          ]),
          const SizedBox(height: 8),
          child,
        ]),
      );
  Widget _discret(String t) => Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600));
  Widget _txt(String t, {Color? c, FontWeight? w}) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: c ?? _ink, fontWeight: w, height: 1.35)),
      );
  String? _f(String k) => (_fiche?[k]?.toString() ?? '').trim().isEmpty ? null : _fiche![k].toString().trim();

  Future<void> _ouvrirSeance({Map<String, dynamic>? rdv, Map<String, dynamic>? seance}) async {
    final r = rdv == null ? null : {...rdv, '_prestation': _prestation(rdv)};
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => ToilettageSeancePage(animalId: widget.animalId, animalNom: widget.animalNom, rdv: r, seance: seance)));
    if (ok == true) _charger();
  }

  @override
  Widget build(BuildContext context) {
    final enCours = _rdvs.where((r) {
      final e = etapeToilettage(r);
      return e == EtapeToilettage.arrive || e == EtapeToilettage.enCours || e == EtapeToilettage.pret;
    }).firstOrNull;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
        title: Text(widget.animalNom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white, labelColor: Colors.white, unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12.5),
          tabs: const [Tab(text: 'Synthèse'), Tab(text: 'Prestations'), Tab(text: 'Consignes'), Tab(text: 'Historique')],
        ),
      ),
      body: Column(children: [
        ProAnimalEntete(animalId: widget.animalId, catPro: 'toilettage',
            statut: enCours != null ? styleEtape(etapeToilettage(enCours)).label : null),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: _teal))
            : TabBarView(controller: _tabs, children: [_synthese(), _prestationsTab(), _consignes(), _historique()])),
      ]),
    );
  }

  // Synthèse ---------------------------------------------------------------

  Widget _synthese() {
    final p = _aVenir.firstOrNull;
    final derniere = _terminees.firstOrNull;
    final derniereSeance = derniere == null ? _seances.firstOrNull : (_seanceDe(derniere) ?? _seances.firstOrNull);
    final apres = derniereSeance == null ? null
        : _photos.where((x) => x['type'] == 'apres' && x['rdv_id']?.toString() == derniereSeance['rdv_id']?.toString()).lastOrNull;
    final alertes = <(String, Color)>[
      for (final a in _allergies) if (_allergieLabel(a).isNotEmpty) ('Allergie déclarée : ${_allergieLabel(a)}', _rouge),
      for (final t in _traitements.where(_traitementEnCours)) ('Traitement en cours : ${t['nom'] ?? 'traitement'}', _ambre),
      if (_f('produits_a_eviter') != null) ('Produits à éviter : ${_f('produits_a_eviter')}', _rouge),
      if (_f('zones_sensibles') != null) ('Zones sensibles : ${_f('zones_sensibles')}', _ambre),
      if (_f('comportement_manipulation') != null) ('Comportement : ${_f('comportement_manipulation')}', _ambre),
      if (_tolerance != null && _tolerance != 'bonne') ('Séchoir : ${labelToleranceSechoir(_tolerance)}', _ambre),
    ];
    return RefreshIndicator(
      onRefresh: _charger, color: _teal,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
        _carte('Prochain rendez-vous', Icons.event_outlined, p == null
            ? _discret('Aucun rendez-vous à venir.')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _txt(_prestation(p), w: FontWeight.w700),
                _txt('${_jour(_debut(p))} à ${_hm(_debut(p))} · ${(p['duree_minutes'] as num?)?.toInt() ?? 60} min'),
                if (_employes[p['employe_id']?.toString()] != null) _txt('Toiletteur : ${_employes[p['employe_id']?.toString()]}'),
                if ((p['notes_client']?.toString() ?? '').trim().isNotEmpty) _txt('Demande du client : ${p['notes_client'].toString().trim()}', c: _ambre),
              ])),
        _carte('Alertes importantes', Icons.priority_high_rounded, alertes.isEmpty
            ? _discret('Aucune alerte renseignée.')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final a in alertes) _txt(a.$1, c: a.$2)])),
        _carte('Coupe habituelle', Icons.content_cut, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_f('coupe_habituelle') == null && _f('longueur_coupe') == null && _f('type_poil') == null)
            _discret('Non renseignée — à compléter dans Consignes.'),
          if (_f('type_poil') != null) _txt('Poil : ${_f('type_poil')}'),
          if (_f('coupe_habituelle') != null) _txt(_f('coupe_habituelle')!),
          if (_f('longueur_coupe') != null) _txt('Longueur : ${_f('longueur_coupe')}'),
          if (_f('shampooing_prefere') != null) _txt('Shampooing : ${_f('shampooing_prefere')}'),
        ]), action: TextButton(onPressed: () => _tabs.animateTo(2), child: const Text('Modifier', style: TextStyle(fontFamily: 'Galey')))),
        _carte('Dernière prestation', Icons.history, derniere == null && derniereSeance == null
            ? _discret('Aucune prestation terminée.')
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (derniere != null) _txt('${_prestation(derniere)} — ${_jour(_debut(derniere))}', w: FontWeight.w700),
                  if (derniereSeance != null && ((derniereSeance['travaux'] as List?) ?? []).isNotEmpty)
                    _txt(((derniereSeance['travaux'] as List).map((e) => labelTravailToilettage(e.toString()))).join(', ')),
                  if ((derniereSeance?['cooperation']?.toString() ?? '').isNotEmpty)
                    _txt('Comportement : ${labelCooperationToilettage(derniereSeance!['cooperation']?.toString())}'),
                  if ((derniereSeance?['precautions']?.toString() ?? '').isNotEmpty)
                    _txt('Précautions : ${derniereSeance!['precautions']}', c: _ambre),
                  if (derniere != null && derniereSeance == null)
                    TextButton(onPressed: () => _ouvrirSeance(rdv: derniere), style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        child: const Text('Remplir la fiche technique', style: TextStyle(fontFamily: 'Galey', color: _teal))),
                ])),
                if (apres != null)
                  ClipRRect(borderRadius: BorderRadius.circular(10),
                      child: Image.network(apres['url'].toString(), width: 72, height: 72, fit: BoxFit.cover)),
              ])),
        _carte('Fréquence', Icons.repeat, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _txt('${_terminees.length} prestation${_terminees.length > 1 ? 's' : ''} terminée${_terminees.length > 1 ? 's' : ''}'),
          if (_frequence != null) _txt('Rythme : $_frequence'),
          if (derniere != null) _txt('Dernière visite : ${_jour(_debut(derniere))}'),
        ])),
      ]),
    );
  }

  // Prestations ------------------------------------------------------------

  Widget _lignePrestation(Map<String, dynamic> r) {
    final st = styleEtape(etapeToilettage(r));
    final s = _seanceDe(r);
    final passee = !_aVenir.contains(r);
    final emp = _employes[r['employe_id']?.toString()];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE6E8E6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(_prestation(r), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink))),
          DashBadge(st.label, fg: st.fg, bg: st.bg),
        ]),
        const SizedBox(height: 3),
        _discret('${_jour(_debut(r))} à ${_hm(_debut(r))} · ${(r['duree_minutes'] as num?)?.toInt() ?? 60} min${emp != null && emp.isNotEmpty ? ' · $emp' : ''}'),
        if ((r['notes_client']?.toString() ?? '').trim().isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 3), child: _txt('Demande : ${r['notes_client'].toString().trim()}', c: _ambre)),
        if (passee && r['statut'] != 'absent')
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(
            onPressed: () => _ouvrirSeance(rdv: r, seance: s),
            icon: Icon(s == null ? Icons.note_add_outlined : Icons.description_outlined, size: 16),
            label: Text(s == null ? 'Remplir la fiche technique' : 'Fiche technique${s['partage_proprietaire'] == true ? ' · compte rendu partagé' : ''}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
            style: TextButton.styleFrom(foregroundColor: _teal, padding: EdgeInsets.zero),
          )),
      ]),
    );
  }

  Widget _prestationsTab() => RefreshIndicator(
        onRefresh: _charger, color: _teal,
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
          _titre('À venir', _aVenir.length),
          if (_aVenir.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: _discret('Aucun rendez-vous à venir.')),
          ..._aVenir.map(_lignePrestation),
          const SizedBox(height: 8),
          _titre('Passées', _passees.length),
          if (_passees.isEmpty) _discret('Aucune prestation passée.'),
          ..._passees.map(_lignePrestation),
        ]),
      );

  Widget _titre(String t, int n) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text('$t ($n)', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5, color: _ink)),
      );

  // Consignes --------------------------------------------------------------

  Future<void> _enregistrerConsignes() async {
    setState(() => _saving = true);
    String? v(String k) => _c[k]!.text.trim().isEmpty ? null : _c[k]!.text.trim();
    final data = {
      for (final k in _champsConsignes) k.$1: v(k.$1),
      'tolerance_sechoir': _tolerance,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      if (_fiche != null) {
        await _supa.from('fiches_toilettage').update(data).eq('id', _fiche!['id']);
      } else {
        final rdv = _rdvs.firstOrNull;
        await _supa.from('fiches_toilettage').insert({
          ...data,
          'pro_uid': FirebaseAuth.instance.currentUser!.uid,
          'pro_profile_id': _pid,
          'animal_id': widget.animalId,
          if (rdv?['client_uid'] != null) 'client_uid': rdv!['client_uid'],
          if (rdv?['client_profile_id'] != null) 'client_profile_id': rdv!['client_profile_id'],
        });
      }
      await _charger();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Consignes enregistrées.', style: TextStyle(fontFamily: 'Galey'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
            e.toString().contains('column') ? 'Migration migration_toilettage_fiche.sql à passer.' : 'Erreur : $e',
            style: const TextStyle(fontFamily: 'Galey'))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _consignes() {
    final demandes = _rdvs.where((r) => (r['notes_client']?.toString() ?? '').trim().isNotEmpty).firstOrNull;
    final traitements = _traitements.where(_traitementEnCours).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
      _carte('Déclaré par le propriétaire', Icons.person_outline, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_allergies.isEmpty && traitements.isEmpty && demandes == null)
          _discret('Rien de déclaré dans le carnet du propriétaire.'),
        for (final a in _allergies) if (_allergieLabel(a).isNotEmpty) _txt('Allergie : ${_allergieLabel(a)}', c: _rouge),
        for (final t in traitements)
          _txt('Traitement : ${t['nom'] ?? 'Traitement'}${(t['posologie']?.toString() ?? '').isNotEmpty ? ' — ${t['posologie']}' : ''}'),
        if (demandes != null) _txt('Dernière demande à la réservation : ${demandes['notes_client'].toString().trim()}'),
        const SizedBox(height: 4),
        Text('Lecture seule : ces informations viennent du carnet de santé et des réservations.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade500)),
      ])),
      _carte('Observations du salon', Icons.content_cut, Column(children: [
        for (final k in _champsConsignes.take(8))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(controller: _c[k.$1], maxLines: 3, minLines: 1, style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(labelText: k.$2, isDense: true, border: const OutlineInputBorder(),
                    labelStyle: const TextStyle(fontFamily: 'Galey'))),
          ),
        DropdownButtonFormField<String>(
          initialValue: _tolerance,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Tolérance au séchoir', isDense: true, border: OutlineInputBorder(),
              labelStyle: TextStyle(fontFamily: 'Galey')),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('Non renseignée', style: TextStyle(fontFamily: 'Galey'))),
            for (final t in kToleranceSechoir) DropdownMenuItem(value: t.$1, child: Text(t.$2, style: const TextStyle(fontFamily: 'Galey'))),
          ],
          onChanged: (v) => setState(() => _tolerance = v),
        ),
        const SizedBox(height: 10),
        for (final k in _champsConsignes.skip(8))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(controller: _c[k.$1], maxLines: 3, minLines: 1, style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(labelText: k.$2, isDense: true, border: const OutlineInputBorder(),
                    labelStyle: const TextStyle(fontFamily: 'Galey'))),
          ),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _saving ? null : _enregistrerConsignes,
          style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12)),
          child: Text(_saving ? 'Enregistrement…' : 'Enregistrer les consignes', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
        )),
        const SizedBox(height: 4),
        Text('Consignes permanentes du salon : reprises à chaque rendez-vous, jamais visibles du propriétaire.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade500)),
      ])),
    ]);
  }

  // Historique -------------------------------------------------------------

  Widget _historique() {
    // Une entrée par fiche technique (plus récente d'abord), avec ses photos.
    if (_seances.isEmpty) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        _discret('Aucune fiche technique pour l\'instant. Remplissez-la depuis l\'onglet Prestations après chaque toilettage.'),
      ]);
    }
    return RefreshIndicator(
      onRefresh: _charger, color: _teal,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
        for (final s in _seances) _ligneHistorique(s),
      ]),
    );
  }

  Widget _ligneHistorique(Map<String, dynamic> s) {
    final rdv = _rdvs.where((r) => r['id']?.toString() == s['rdv_id']?.toString()).firstOrNull;
    final d = DateTime.tryParse(s['date_seance']?.toString() ?? '');
    final photos = _photos.where((p) => s['rdv_id'] != null && p['rdv_id']?.toString() == s['rdv_id']?.toString()).toList();
    final travaux = ((s['travaux'] as List?) ?? []).map((e) => labelTravailToilettage(e.toString())).join(', ');
    return InkWell(
      onTap: () => _ouvrirSeance(rdv: rdv, seance: s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE6E8E6))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text([
              if (d != null) DateFormat('d MMMM yyyy', 'fr_FR').format(d),
              if (rdv != null) _prestation(rdv),
            ].join(' — '), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink))),
            if (s['partage_proprietaire'] == true)
              const DashBadge('Partagé', fg: _teal, bg: Color(0xFFE6F2F3)),
          ]),
          const SizedBox(height: 4),
          if (_employes[s['employe_id']?.toString()] != null) _discret('Toiletteur : ${_employes[s['employe_id']?.toString()]}'),
          if (travaux.isNotEmpty) _txt(travaux),
          if ((s['longueur_coupe']?.toString() ?? '').isNotEmpty) _txt('Longueur : ${s['longueur_coupe']}'),
          if ((s['produits']?.toString() ?? '').isNotEmpty) _txt('Produits : ${s['produits']}'),
          if ((s['cooperation']?.toString() ?? '').isNotEmpty) _txt('Comportement : ${labelCooperationToilettage(s['cooperation']?.toString())}'),
          if ((s['precautions']?.toString() ?? '').isNotEmpty) _txt('Précautions : ${s['precautions']}', c: _ambre),
          if ((s['observations']?.toString() ?? '').isNotEmpty) _txt('Observations : ${s['observations']}'),
          if ((s['compte_rendu']?.toString() ?? '').isNotEmpty) _txt('Compte rendu : ${s['compte_rendu']}'),
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(height: 64, child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => Column(children: [
                ClipRRect(borderRadius: BorderRadius.circular(8),
                    child: Image.network(photos[i]['url'].toString(), width: 48, height: 48, fit: BoxFit.cover)),
                Text(photos[i]['type'] == 'avant' ? 'Avant' : 'Après', style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade600)),
              ]),
            )),
          ],
        ]),
      ),
    );
  }
}
