// Fiche pet-sitter d'un animal (gardes, promenades, visites) — vue métier de
// l'animal : en-tête commun (identité + propriétaire, urgence, personnes
// autorisées), onglets Synthèse · Prestations · Consignes · Historique.
// Données EXISTANTES uniquement : rdv (prestations, heures réelles),
// cles_clients (gestion des clés), pension_updates (comptes rendus express),
// alimentations / allergies / traitements (carnet du propriétaire).
// Miroir site : mes-patients/[id] (onglets pet-sitter).
// Scopé au profil pet-sitter actif (pro_profile_id) — jamais l'uid seul.
import 'package:flutter/material.dart';
import 'package:PetsMatch/widgets/alimentation/plan_alimentation_lecture.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/widgets/animal/pro_animal_entete.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart' show AnimalFichePage;
import 'package:PetsMatch/pages/pro/cles_clients_page.dart';
import 'package:PetsMatch/pages/pro/visite_rapport_sheet.dart';
import 'package:PetsMatch/pages/pro/garde_facture_helper.dart'
    show gardePrestationKey, gardeMotifLabel, estGardeJournee, accesLogementLabel;

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1F2A2E);
const _vert = Color(0xFF2E7D5E);
const _ambre = Color(0xFFD97706);
const _rouge = Color(0xFFB3261E);

class GardeFicheAnimalPage extends StatefulWidget {
  final String animalId;
  final String animalNom;
  final int initialTab;
  const GardeFicheAnimalPage({super.key, required this.animalId, this.animalNom = 'Animal', this.initialTab = 0});

  @override
  State<GardeFicheAnimalPage> createState() => _GardeFicheAnimalPageState();
}

class _GardeFicheAnimalPageState extends State<GardeFicheAnimalPage> with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;
  late final TabController _tabs;
  bool _loading = true;
  Map<String, dynamic>? _animal;
  List<Map<String, dynamic>> _rdvs = [];
  List<Map<String, dynamic>> _cles = [];
  List<Map<String, dynamic>> _crs = [];
  Map<String, dynamic>? _alim;
  List<Map<String, dynamic>> _allergies = [];
  List<Map<String, dynamic>> _traitements = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this, initialIndex: widget.initialTab.clamp(0, 3));
    _charger();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String get _pid => User_Info.activeProfileId;
  List<Map<String, dynamic>> _l(dynamic r) =>
      List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map)));

  Future<void> _charger() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final id = widget.animalId;
    try { _animal = await _supa.from('animaux').select('id, nom, espece').eq('id', id).maybeSingle(); } catch (_) {}
    if (_pid.isNotEmpty) {
      try {
        _rdvs = _l(await _supa.from('rdv').select().eq('pro_profile_id', _pid).eq('animal_id', id)
            .inFilter('statut', ['confirme', 'termine']).order('date_heure', ascending: false).limit(150));
      } catch (_) {}
      try {
        _cles = _l(await _supa.from('cles_clients').select().eq('pro_profile_id', _pid).eq('animal_id', id));
      } catch (_) { _cles = []; }
    }
    if (uid != null) {
      try {
        _crs = _l(await _supa.from('pension_updates').select().eq('pro_uid', uid).eq('animal_id', id)
            .order('created_at', ascending: false).limit(60));
      } catch (_) { _crs = []; }
    }
    try { _alim = await _supa.from('alimentations').select().eq('animal_id', id).maybeSingle(); } catch (_) {}
    try { _allergies = _l(await _supa.from('allergies').select().eq('animal_id', id)); } catch (_) {}
    try { _traitements = _l(await _supa.from('traitements').select().eq('animal_id', id).order('date', ascending: false)); } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  DateTime _debut(Map<String, dynamic> r) => DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal() ?? DateTime(2000);
  DateTime? _reel(Map<String, dynamic> r, String k) => DateTime.tryParse(r[k]?.toString() ?? '')?.toLocal();
  String _hm(DateTime d) => DateFormat('HH:mm').format(d);
  String _jour(DateTime d) => DateFormat('EEE d MMM', 'fr_FR').format(d);
  String _prestation(Map<String, dynamic> r) {
    final k = gardePrestationKey(r['motif']?.toString());
    return k == 'autre'
        ? ((r['motif']?.toString() ?? '').trim().isEmpty ? 'Prestation' : r['motif'].toString().trim())
        : gardeMotifLabel(k, _animal?['espece']?.toString());
  }
  String _horaires(Map<String, dynamic> r) {
    final d = _debut(r);
    if (estGardeJournee(r)) return '${_jour(d)} · journée';
    final fin = d.add(Duration(minutes: (r['duree_minutes'] as num?)?.toInt() ?? 30));
    final reelD = _reel(r, 'arrivee_validee_le');
    final reelF = _reel(r, 'depart_valide_le') ?? _reel(r, 'termine_at');
    return '${_jour(d)} · prévu ${_hm(d)}–${_hm(fin)}'
        '${reelD != null || reelF != null ? ' · réel ${reelD != null ? _hm(reelD) : '?'}–${reelF != null ? _hm(reelF) : '…'}' : ''}';
  }

  List<Map<String, dynamic>> get _aVenir {
    final now = DateTime.now();
    return _rdvs.where((r) => r['statut'] == 'confirme' && _debut(r).add(Duration(minutes: (r['duree_minutes'] as num?)?.toInt() ?? 30)).isAfter(now)).toList()
      ..sort((a, b) => _debut(a).compareTo(_debut(b)));
  }
  List<Map<String, dynamic>> get _passees => _rdvs.where((r) => !_aVenir.contains(r)).toList();
  Map<String, dynamic>? get _prochaine => _aVenir.isEmpty ? null : _aVenir.first;
  Map<String, dynamic>? get _derniereAvecConsignes =>
      _rdvs.where((r) => (r['notes_client']?.toString() ?? '').trim().isNotEmpty).firstOrNull;

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
  Widget _txt(String t, {Color? c, FontWeight? w, double taille = 13.5}) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: taille, color: c ?? _ink, fontWeight: w, height: 1.35)),
      );

  Future<void> _compteRendu(Map<String, dynamic> r) async {
    final ok = await showVisiteRapportSheet(context, r);
    if (ok) _charger();
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final nom = (_animal?['nom'] ?? widget.animalNom).toString();
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
        title: Text(nom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white, labelColor: Colors.white, unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12.5),
          tabs: const [Tab(text: 'Synthèse'), Tab(text: 'Prestations'), Tab(text: 'Consignes'), Tab(text: 'Historique')],
        ),
      ),
      body: Column(children: [
        ProAnimalEntete(animalId: widget.animalId, catPro: 'garde',
            statut: _prochaine != null && _debut(_prochaine!).isBefore(DateTime.now()) ? 'Prestation en cours' : null),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: _teal))
            : TabBarView(controller: _tabs, children: [_synthese(), _prestations(), _consignes(), _historique()])),
      ]),
    );
  }

  // Synthèse ---------------------------------------------------------------

  Widget _synthese() {
    final p = _prochaine;
    final consignes = (p?['notes_client'] ?? _derniereAvecConsignes?['notes_client'])?.toString().trim() ?? '';
    final acces = accesLogementLabel((p ?? _rdvs.firstOrNull)?['acces_logement']?.toString());
    final cle = _cles.where((c) => c['statut'] == 'en_possession').firstOrNull;
    final dernierCr = _crs.firstOrNull;
    return RefreshIndicator(
      onRefresh: _charger, color: _teal,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
        _carte(p != null && _debut(p).isBefore(DateTime.now()) ? 'Prestation en cours' : 'Prochaine prestation', Icons.event_outlined, p == null
            ? _discret('Aucune prestation à venir.')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _txt(_prestation(p), w: FontWeight.w700),
                _txt(_horaires(p)),
                if ((p['lieu']?.toString() ?? '').isNotEmpty) _txt('Lieu : ${p['lieu']}'),
              ])),
        _carte('Consignes essentielles', Icons.priority_high_rounded, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (consignes.isNotEmpty) _txt(consignes),
          if (acces.isNotEmpty) _txt('Accès au logement : $acces'),
          for (final a in _allergies) _txt('Allergie : ${a['nom'] ?? a['allergene'] ?? a['description'] ?? ''}', c: _rouge),
          if (consignes.isEmpty && acces.isEmpty && _allergies.isEmpty) _discret('Aucune consigne transmise.'),
        ]), action: TextButton(onPressed: () => _tabs.animateTo(2), child: const Text('Toutes', style: TextStyle(fontFamily: 'Galey')))),
        _carte('Clés', Icons.vpn_key_outlined, cle == null
            ? _discret('Aucune clé en votre possession pour cet animal.')
            : _txt('${cle['description'] ?? 'Clé'} — en votre possession'),
            action: TextButton(
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const ClesClientsPage()));
                _charger();
              },
              child: const Text('Gérer', style: TextStyle(fontFamily: 'Galey')))),
        _carte('Dernier compte rendu', Icons.article_outlined, dernierCr == null
            ? _discret('Aucun compte rendu envoyé.')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _txt(DateFormat('dd/MM/yyyy à HH:mm').format(DateTime.parse(dernierCr['created_at'].toString()).toLocal()),
                    c: dernierCr['incident'] == true ? _rouge : Colors.grey.shade600, taille: 12),
                _txt((dernierCr['note']?.toString() ?? 'Photo partagée'), taille: 13),
              ])),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnimalFichePage(
              animalId: widget.animalId, readOnly: true, vetMode: true))),
          icon: const Icon(Icons.badge_outlined, size: 18),
          label: const Text('Identité, carnet de santé et alimentation (lecture)', style: TextStyle(fontFamily: 'Galey')),
        ),
      ]),
    );
  }

  // Prestations ------------------------------------------------------------

  Widget _lignePrestation(Map<String, dynamic> r) {
    final termine = r['statut'] == 'termine';
    final avecCr = _crs.any((c) => c['rdv_id']?.toString() == r['id']?.toString());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_prestation(r), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5, color: _ink)),
          Text(_horaires(r), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade700)),
          if ((r['lieu']?.toString() ?? '').isNotEmpty)
            Text(r['lieu'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(termine ? 'Terminée' : 'Confirmée', style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, fontWeight: FontWeight.w700,
              color: termine ? Colors.grey.shade600 : _teal)),
          if (termine && !avecCr && !estGardeJournee(r))
            TextButton(onPressed: () => _compteRendu(r),
                child: const Text('Compte rendu', style: TextStyle(fontFamily: 'Galey', fontSize: 12))),
          if (avecCr) const Text('CR envoyé', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: _vert)),
        ]),
      ]),
    );
  }

  Widget _prestations() {
    final av = _aVenir, pa = _passees;
    return RefreshIndicator(
      onRefresh: _charger, color: _teal,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
        _carte('À venir', Icons.event_available_outlined, av.isEmpty ? _discret('Aucune.')
            : Column(children: [for (final r in av.take(20)) _lignePrestation(r)])),
        _carte('Passées', Icons.history, pa.isEmpty ? _discret('Aucune.')
            : Column(children: [for (final r in pa.take(30)) _lignePrestation(r)])),
      ]),
    );
  }

  // Consignes --------------------------------------------------------------

  Widget _consignes() {
    final a = _alim;
    final traitementsEnCours = _traitements.where((t) {
      final fin = DateTime.tryParse(t['date_fin']?.toString() ?? '');
      return fin == null || !fin.isBefore(DateTime.now());
    }).toList();
    final avecConsignes = _rdvs.where((r) => (r['notes_client']?.toString() ?? '').trim().isNotEmpty).take(5).toList();
    final acces = {for (final r in _rdvs) if (accesLogementLabel(r['acces_logement']?.toString()).isNotEmpty) accesLogementLabel(r['acces_logement']?.toString())};
    return RefreshIndicator(
      onRefresh: _charger, color: _teal,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
        _carte('Alimentation', Icons.restaurant_outlined,
            PlanAlimentationLecture.depuisLigne(a, (_animal?['espece'] ?? '').toString(),
                nomAnimal: (_animal?['nom'] ?? '').toString())),
        _carte('Traitements et précautions', Icons.medication_outlined, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final t in traitementsEnCours)
            _txt('${t['nom'] ?? 'Traitement'}${(t['posologie']?.toString() ?? '').isNotEmpty ? ' — ${t['posologie']}' : ''}'),
          for (final al in _allergies) _txt('Allergie : ${al['nom'] ?? al['allergene'] ?? al['description'] ?? ''}', c: _rouge),
          if (traitementsEnCours.isEmpty && _allergies.isEmpty) _discret('Aucun traitement en cours ni allergie connue.'),
        ])),
        _carte('Instructions d\'accès', Icons.door_front_door_outlined, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final x in acces) _txt(x),
          for (final c in _cles) _txt('Clé : ${c['description'] ?? 'Clé'} (${c['statut'] == 'en_possession' ? 'en votre possession' : 'rendue'})'),
          if (acces.isEmpty && _cles.isEmpty) _discret('Aucune instruction d\'accès.'),
          const SizedBox(height: 4),
          Text('Aucun code d\'accès n\'est stocké dans la fiche.', style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
        ])),
        _carte('Consignes des réservations', Icons.notes_outlined, avecConsignes.isEmpty
            ? _discret('Aucune consigne saisie par le propriétaire.')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final r in avecConsignes) ...[
                  _txt(DateFormat('dd/MM/yyyy').format(_debut(r)), c: Colors.grey.shade600, taille: 12),
                  _txt(r['notes_client'].toString()),
                ],
              ])),
      ]),
    );
  }

  // Historique -------------------------------------------------------------

  Widget _historique() {
    final faites = _rdvs.where((r) => r['statut'] == 'termine').toList();
    return RefreshIndicator(
      onRefresh: _charger, color: _teal,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
        _carte('Comptes rendus et photos', Icons.photo_library_outlined, _crs.isEmpty
            ? _discret('Aucun compte rendu.')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final c in _crs.take(20))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if ((c['photo_url']?.toString() ?? '').isNotEmpty) ...[
                        ClipRRect(borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(imageUrl: c['photo_url'].toString(), width: 52, height: 52, fit: BoxFit.cover)),
                        const SizedBox(width: 10),
                      ],
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${DateFormat('dd/MM/yyyy à HH:mm').format(DateTime.parse(c['created_at'].toString()).toLocal())}'
                            '${c['incident'] == true ? ' · incident' : ''}',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: c['incident'] == true ? _rouge : Colors.grey.shade600)),
                        if ((c['note']?.toString() ?? '').isNotEmpty)
                          Text(c['note'].toString(), style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.35)),
                      ])),
                    ]),
                  ),
              ])),
        _carte('Prestations réalisées (${faites.length})', Icons.task_alt, faites.isEmpty
            ? _discret('Aucune prestation terminée.')
            : Column(children: [
                for (final r in faites.take(30))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      const Icon(Icons.check_circle_outline, size: 16, color: _vert),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${_prestation(r)} · ${_horaires(r)}',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5))),
                    ]),
                  ),
              ])),
        if (_rdvs.any((r) => r['statut'] == 'confirme' && _debut(r).isBefore(DateTime.now())))
          Text('Des prestations passées ne sont pas encore marquées terminées (agenda).',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _ambre)),
      ]),
    );
  }
}
