import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/pro/owner_contact.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:url_launcher/url_launcher.dart';

const _kEducationTeal = Color(0xFF0C5C6C);
const _kEducationPurple = Color(0xFF7B5EA7);

class EducationPlanningPage extends StatefulWidget {
  const EducationPlanningPage({super.key});
  @override
  State<EducationPlanningPage> createState() => _EducationPlanningPageState();
}

class _EducationPlanningPageState extends State<EducationPlanningPage> {
  final _supa = Supabase.instance.client;

  static const List<String> _jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

  List<Map<String, dynamic>> _rdvs = [];
  List<Map<String, dynamic>> _cours = [];
  Map<String, int> _participantsCount = {};
  bool _loading = true;
  DateTime _windowStart = DateTime.now();
  static const int _days = 7;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _windowStart = DateTime(now.year, now.month, now.day);
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _loading = true);
    try {
      final windowEnd = _windowStart.add(const Duration(days: _days));
      final results = await Future.wait([
        _supa.from('rdv').select().eq('pro_uid', uid)
            .gte('date_heure', _windowStart.toIso8601String())
            .lt('date_heure', windowEnd.toIso8601String())
            .neq('statut', 'refuse')
            .order('date_heure'),
        _supa.from('cours_collectifs').select().eq('pro_uid', uid)
            .gte('date_heure', _windowStart.toIso8601String())
            .lt('date_heure', windowEnd.toIso8601String())
            .neq('statut', 'annule')
            .order('date_heure'),
      ]);
      final cours = List<Map<String, dynamic>>.from(results[1] as List);
      final coursIds = cours.map((c) => c['id'] as String).toList();
      final counts = <String, int>{};
      if (coursIds.isNotEmpty) {
        final participants = await _supa.from('cours_collectifs_participants')
            .select('cours_id')
            .inFilter('cours_id', coursIds)
            .neq('statut', 'annule');
        for (final p in participants as List) {
          final cid = p['cours_id'] as String;
          counts[cid] = (counts[cid] ?? 0) + 1;
        }
      }
      final rdvs = List<Map<String, dynamic>>.from(results[0] as List);
      // Résout nom du client + nom de l'animal pour l'affichage / la fiche.
      final rClientUids = rdvs.map((r) => r['client_uid']?.toString()).whereType<String>().toSet().toList();
      final rAnimalIds = rdvs.map((r) => r['animal_id']?.toString()).whereType<String>().toSet().toList();
      final rNames = <String, String>{};
      final rAnimalNames = <String, String>{};
      if (rClientUids.isNotEmpty) {
        final users = await _supa.from('user_profiles')
            .select('uid, firstname, lastname').inFilter('uid', rClientUids).eq('is_main', true);
        for (final u in users as List) {
          rNames[u['uid'] as String] = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
        }
      }
      if (rAnimalIds.isNotEmpty) {
        final animaux = await _supa.from('animaux').select('id, nom').inFilter('id', rAnimalIds);
        for (final a in animaux as List) {
          rAnimalNames[a['id'].toString()] = a['nom']?.toString() ?? 'Animal';
        }
      }
      for (final r in rdvs) {
        r['_client_nom'] = (rNames[r['client_uid']]?.isNotEmpty ?? false)
            ? rNames[r['client_uid']]
            : (r['client_nom_manuel']?.toString().isNotEmpty ?? false ? r['client_nom_manuel'] : 'Client');
        r['_animal_nom'] = rAnimalNames[r['animal_id']?.toString()] ?? '';
      }
      if (mounted) {
        setState(() {
          _rdvs = rdvs;
          _cours = cours;
          _participantsCount = counts;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shiftWindow(int days) {
    setState(() => _windowStart = _windowStart.add(Duration(days: days)));
    _load();
  }

  List<Map<String, dynamic>> _sessionsForDay(DateTime day) {
    final sessions = <Map<String, dynamic>>[];
    for (final r in _rdvs) {
      final d = DateTime.tryParse(r['date_heure']?.toString() ?? '');
      if (d != null && _sameDay(d, day)) sessions.add({...r, '_kind': 'rdv'});
    }
    for (final c in _cours) {
      final d = DateTime.tryParse(c['date_heure']?.toString() ?? '');
      if (d != null && _sameDay(d, day)) sessions.add({...c, '_kind': 'cours'});
    }
    sessions.sort((a, b) => (a['date_heure'] as String).compareTo(b['date_heure'] as String));
    return sessions;
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _createCoursCollectif() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CoursCollectifSheet(),
    );
    if (result == true) _load();
  }

  void _openCours(Map<String, dynamic> cours) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CoursCollectifDetailPage(coursId: cours['id'] as String),
    )).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final days = List.generate(_days, (i) => _windowStart.add(Duration(days: i)));

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _kEducationTeal,
        foregroundColor: Colors.white,
        title: const Text('Planning des cours', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shiftWindow(-7)),
          IconButton(icon: const Icon(Icons.today_outlined), tooltip: 'Aujourd\'hui', onPressed: () {
            setState(() => _windowStart = today);
            _load();
          }),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shiftWindow(7)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCoursCollectif,
        backgroundColor: _kEducationPurple,
        icon: const Icon(Icons.groups_outlined),
        label: const Text('Cours collectif', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kEducationTeal))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: days.length,
              itemBuilder: (_, i) {
                final day = days[i];
                final sessions = _sessionsForDay(day);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _sameDay(day, today) ? _kEducationTeal : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          DateFormat('EEEE d MMMM', 'fr_FR').format(day),
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700,
                              color: _sameDay(day, today) ? Colors.white : Colors.black87),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    if (sessions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('Aucune séance', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
                      )
                    else
                      for (final s in sessions) _sessionCard(s),
                  ]),
                );
              },
            ),
    );
  }

  Widget _sessionCard(Map<String, dynamic> s) {
    final isCours = s['_kind'] == 'cours';
    final d = DateTime.tryParse(s['date_heure']?.toString() ?? '');
    final heure = d != null ? DateFormat('HH:mm').format(d) : '--:--';
    final titre = isCours
        ? (s['titre']?.toString() ?? 'Cours collectif')
        : (s['motif']?.toString() ?? 'RDV');
    final estRecurrent = isCours && s['serie_id'] != null;
    final clientNom = (s['_client_nom']?.toString() ?? '').trim();
    final animalNom = (s['_animal_nom']?.toString() ?? '').trim();
    final sousTitre = isCours
        ? '${_participantsCount[s['id']] ?? 0} / ${s['capacite_max']} inscrits'
            '${estRecurrent && d != null ? ' · chaque ${_jours[d.weekday - 1]}' : ''}'
        : [
            if (clientNom.isNotEmpty) clientNom,
            if (animalNom.isNotEmpty) animalNom,
            '${s['duree_minutes'] ?? 60} min',
          ].join(' · ');

    return GestureDetector(
      onTap: isCours ? () => _openCours(s) : () => _openRdvDetail(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isCours ? _kEducationPurple.withValues(alpha: 0.3) : Colors.grey.shade200),
        ),
        child: Row(children: [
          Container(
            width: 4, height: 36,
            decoration: BoxDecoration(
              color: isCours ? _kEducationPurple : _kEducationTeal,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 48, child: Text(heure, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13))),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (estRecurrent) const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.repeat, size: 13, color: _kEducationPurple),
              ),
              Flexible(child: Text(titre, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13))),
            ]),
            Text(sousTitre, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          ])),
          if (!isCours && s['statut'] == 'demande')
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(20)),
              child: Text('à confirmer', style: TextStyle(fontFamily: 'Galey', fontSize: 9, fontWeight: FontWeight.w700, color: Colors.orange.shade700)),
            ),
          Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
        ]),
      ),
    );
  }

  void _openRdvDetail(Map<String, dynamic> rdv) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _RdvDetailSheet(rdv: rdv),
    ).then((changed) { if (changed == true) _load(); });
  }
}

// ── Création d'un cours collectif ──────────────────────────────────────────

class _CoursCollectifSheet extends StatefulWidget {
  const _CoursCollectifSheet();
  @override
  State<_CoursCollectifSheet> createState() => _CoursCollectifSheetState();
}

class _CoursCollectifSheetState extends State<_CoursCollectifSheet> {
  final _supa = Supabase.instance.client;
  final _titreCtrl = TextEditingController();
  final _lieuCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _capaciteCtrl = TextEditingController(text: '6');
  final _dureeCtrl = TextEditingController(text: '90');
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _heure = const TimeOfDay(hour: 18, minute: 0);
  bool _saving = false;
  bool _recurrent = false;
  DateTime? _dateFin;
  static const int _horizonSemaines = 8;

  @override
  void dispose() {
    _titreCtrl.dispose(); _lieuCtrl.dispose(); _notesCtrl.dispose();
    _capaciteCtrl.dispose(); _dureeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _titreCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final dateHeure = DateTime(_date.year, _date.month, _date.day, _heure.hour, _heure.minute);
      final dureeMinutes = int.tryParse(_dureeCtrl.text.trim()) ?? 90;
      final capaciteMax = int.tryParse(_capaciteCtrl.text.trim()) ?? 6;
      final titre = _titreCtrl.text.trim();
      final lieu = _lieuCtrl.text.trim().isEmpty ? null : _lieuCtrl.text.trim();
      final notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
      final profileId = User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null;

      String? serieId;
      if (_recurrent) {
        final serie = await _supa.from('cours_collectifs_series').insert({
          'pro_uid': uid,
          'pro_profile_id': profileId,
          'titre': titre,
          'date_debut': dateHeure.toIso8601String(),
          'duree_minutes': dureeMinutes,
          'capacite_max': capaciteMax,
          'lieu': lieu,
          'notes': notes,
          if (_dateFin != null) 'date_fin': _dateFin!.toIso8601String().substring(0, 10),
        }).select('id').single();
        serieId = serie['id'] as String;
      }

      // Horizon de génération : jusqu'à la date de fin choisie si elle est
      // plus proche, sinon _horizonSemaines (le reste est pris en charge par
      // la Cloud Function generateCoursCollectifsOccurrences chaque jour).
      var horizonFin = dateHeure.add(Duration(days: 7 * (_horizonSemaines - 1)));
      if (_recurrent && _dateFin != null && _dateFin!.isBefore(horizonFin)) {
        horizonFin = DateTime(_dateFin!.year, _dateFin!.month, _dateFin!.day, 23, 59);
      }
      final occurrences = <DateTime>[dateHeure];
      if (_recurrent) {
        var next = dateHeure.add(const Duration(days: 7));
        while (!next.isAfter(horizonFin)) {
          occurrences.add(next);
          next = next.add(const Duration(days: 7));
        }
      }

      for (final occDate in occurrences) {
        final inserted = await _supa.from('cours_collectifs').insert({
          'pro_uid': uid,
          'pro_profile_id': profileId,
          'titre': titre,
          'date_heure': occDate.toIso8601String(),
          'duree_minutes': dureeMinutes,
          'capacite_max': capaciteMax,
          'lieu': lieu,
          'notes': notes,
          if (serieId != null) 'serie_id': serieId,
        }).select('id').single();
        // Visible dans "Mon agenda" (même mécanisme que les RDV confirmés).
        try {
          await _supa.from('agenda_events').insert({
            'uid': uid,
            'titre': '👥 $titre',
            'type': 'cours_collectif',
            'date_debut': occDate.toIso8601String(),
            'duree_minutes': dureeMinutes,
            'couleur': 'cours:${inserted['id']}',
            'pro_profile_id': profileId,
          });
        } catch (_) {}
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFFF8F8F6), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.95, expand: false,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          children: [
            const Text('Nouveau cours collectif',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 16),
            TextField(controller: _titreCtrl, decoration: const InputDecoration(
                labelText: 'Titre du cours', hintText: 'Ex : Éducation chiot', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () async {
                  final picked = await showDatePicker(context: context, initialDate: _date,
                      firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (picked != null) setState(() => _date = picked);
                },
                child: Text(DateFormat('dd/MM/yyyy').format(_date)),
              )),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(
                onPressed: () async {
                  final picked = await showTimePicker(context: context, initialTime: _heure);
                  if (picked != null) setState(() => _heure = picked);
                },
                child: Text(_heure.format(context)),
              )),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _dureeCtrl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Durée (min)', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _capaciteCtrl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Places max', border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _lieuCtrl, decoration: const InputDecoration(
                labelText: 'Lieu', hintText: 'Adresse ou "à domicile"', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _notesCtrl, maxLines: 3, decoration: const InputDecoration(
                labelText: 'Notes (optionnel)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _recurrent ? _kEducationPurple.withValues(alpha: 0.06) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _recurrent ? _kEducationPurple : Colors.grey.shade300),
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Cours récurrent (chaque semaine)',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13,
                          color: _recurrent ? _kEducationPurple : Colors.black87)),
                  const SizedBox(height: 2),
                  Text(
                    _recurrent
                        ? 'Se répète chaque ${DateFormat('EEEE', 'fr_FR').format(_date)} à ${_heure.format(context)}'
                        : 'Une seule séance, ponctuelle',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600),
                  ),
                ])),
                const SizedBox(width: 8),
                Switch(value: _recurrent, activeThumbColor: _kEducationPurple, onChanged: (v) => setState(() => _recurrent = v)),
              ]),
            ),
            if (_recurrent) ...[
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dateFin ?? _date.add(const Duration(days: 56)),
                      firstDate: _date.add(const Duration(days: 7)),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (picked != null) setState(() => _dateFin = picked);
                  },
                  child: Text(_dateFin == null
                      ? 'Pas de date de fin'
                      : 'Jusqu\'au ${DateFormat('dd/MM/yyyy').format(_dateFin!)}'),
                )),
                if (_dateFin != null) IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Retirer la date de fin',
                  onPressed: () => setState(() => _dateFin = null),
                ),
              ]),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(backgroundColor: _kEducationPurple, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Créer le cours', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Détail d'un cours collectif : liste des participants ──────────────────

class CoursCollectifDetailPage extends StatefulWidget {
  final String coursId;
  const CoursCollectifDetailPage({super.key, required this.coursId});
  @override
  State<CoursCollectifDetailPage> createState() => _CoursCollectifDetailPageState();
}

class _CoursCollectifDetailPageState extends State<CoursCollectifDetailPage> {
  final _supa = Supabase.instance.client;
  Map<String, dynamic>? _cours;
  List<Map<String, dynamic>> _participants = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cours = await _supa.from('cours_collectifs').select().eq('id', widget.coursId).maybeSingle();
      final participants = await _supa.from('cours_collectifs_participants')
          .select().eq('cours_id', widget.coursId).neq('statut', 'annule').order('created_at');
      final list = List<Map<String, dynamic>>.from(participants as List);
      final clientUids = list.map((p) => p['client_uid']?.toString()).whereType<String>().toSet().toList();
      final animalIds = list.map((p) => p['animal_id']?.toString()).whereType<String>().toList();
      final names = <String, String>{};
      final animalNames = <String, String>{};
      if (clientUids.isNotEmpty) {
        final users = await _supa.from('user_profiles').select('uid, firstname, lastname').inFilter('uid', clientUids).eq('is_main', true);
        for (final u in users as List) {
          names[u['uid'] as String] = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
        }
      }
      if (animalIds.isNotEmpty) {
        final animaux = await _supa.from('animaux').select('id, nom').inFilter('id', animalIds);
        for (final a in animaux as List) {
          animalNames[a['id'] as String] = a['nom']?.toString() ?? 'Animal';
        }
      }
      for (final p in list) {
        p['_client_nom'] = names[p['client_uid']]?.isNotEmpty == true
            ? names[p['client_uid']]
            : (p['client_nom_manuel']?.toString().isNotEmpty == true ? p['client_nom_manuel'] : 'Client');
        p['_animal_nom'] = animalNames[p['animal_id']?.toString()] ?? '';
      }
      if (mounted) setState(() { _cours = cours; _participants = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateStatut(String participantId, String statut) async {
    final participant = _participants.firstWhere((p) => p['id'] == participantId, orElse: () => {});
    final ancien = participant['statut'];
    await _supa.from('cours_collectifs_participants').update({'statut': statut}).eq('id', participantId);
    // Une place occupée (confirmée OU en attente de confirmation) se libère
    // en cas d'annulation → on promeut la liste d'attente.
    if (statut == 'annule' && (ancien == 'inscrit' || ancien == 'demande')) await _promouvoirListeAttente();
    if (statut == 'annule' && ancien == 'demande') await _notifierDecisionDemande(participant, confirme: false);
    _load();
  }

  Future<void> _confirmerDemande(String participantId) async {
    final participant = _participants.firstWhere((p) => p['id'] == participantId, orElse: () => {});
    await _supa.from('cours_collectifs_participants').update({'statut': 'inscrit'}).eq('id', participantId);
    await _notifierDecisionDemande(participant, confirme: true);
    _load();
  }

  Future<void> _notifierDecisionDemande(Map<String, dynamic> participant, {required bool confirme}) async {
    if (participant['client_uid'] == null) return; // participant manuel, pas de compte à notifier
    try {
      final titre = _cours?['titre']?.toString() ?? 'un cours';
      final d = DateTime.tryParse(_cours?['date_heure']?.toString() ?? '');
      final dateStr = d != null ? DateFormat('dd/MM à HH:mm').format(d) : '';
      await _supa.from('notifications').insert({
        'uid': participant['client_uid'],
        'type': confirme ? 'cours_collectif_confirme' : 'cours_collectif_refuse',
        'title': confirme ? 'Inscription confirmée !' : 'Inscription refusée',
        'body': confirme
            ? 'Votre inscription au cours "$titre"${dateStr.isNotEmpty ? ' du $dateStr' : ''} est confirmée.'
            : 'Votre demande d\'inscription au cours "$titre"${dateStr.isNotEmpty ? ' du $dateStr' : ''} n\'a pas été retenue.',
        if (participant['client_profile_id'] != null) 'profile_id': participant['client_profile_id'],
        'data': <String, dynamic>{'coursId': widget.coursId},
        'read': false,
      });
    } catch (_) {}
  }

  /// Promeut le plus ancien participant en liste d'attente de ce cours quand
  /// une place se libère (retrait ou absence gérée en amont par le pro).
  Future<void> _promouvoirListeAttente() async {
    try {
      final attente = await _supa.from('cours_collectifs_participants')
          .select().eq('cours_id', widget.coursId).eq('statut', 'en_attente')
          .order('created_at').limit(1);
      if (attente.isEmpty) return;
      final row = attente.first;
      await _supa.from('cours_collectifs_participants').update({'statut': 'inscrit'}).eq('id', row['id']);
      final titre = _cours?['titre']?.toString() ?? 'un cours';
      final d = DateTime.tryParse(_cours?['date_heure']?.toString() ?? '');
      final dateStr = d != null ? DateFormat('dd/MM à HH:mm').format(d) : '';
      await _supa.from('notifications').insert({
        'uid': row['client_uid'],
        'type': 'cours_collectif_place_liberee',
        'title': 'Une place s\'est libérée !',
        'body': 'Vous êtes maintenant inscrit au cours "$titre"${dateStr.isNotEmpty ? ' du $dateStr' : ''}.',
        if (row['client_profile_id'] != null) 'profile_id': row['client_profile_id'],
        'data': <String, dynamic>{'coursId': widget.coursId},
        'read': false,
      });
    } catch (_) {}
  }

  Future<void> _cancelCours() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler ce cours ?'),
        content: const Text('Les participants ne seront pas notifiés automatiquement.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Oui, annuler')),
        ],
      ),
    );
    if (confirm != true) return;
    await _supa.from('cours_collectifs').update({'statut': 'annule'}).eq('id', widget.coursId);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _cancelSerie() async {
    final serieId = _cours?['serie_id']?.toString();
    if (serieId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler toute la série ?'),
        content: const Text('Toutes les séances à venir de ce cours récurrent seront annulées. '
            'Les séances passées restent inchangées. Les participants ne seront pas notifiés automatiquement.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Oui, tout annuler')),
        ],
      ),
    );
    if (confirm != true) return;
    await _supa.from('cours_collectifs_series').update({'statut': 'annule'}).eq('id', serieId);
    await _supa.from('cours_collectifs')
        .update({'statut': 'annule'})
        .eq('serie_id', serieId)
        .gt('date_heure', DateTime.now().toIso8601String());
    if (mounted) Navigator.pop(context);
  }

  // Ajout manuel d'un participant sans compte (client au téléphone) — même
  // esprit que rdv.client_nom_manuel/client_telephone_manuel pour les RDV
  // individuels. Ajouté directement en 'inscrit' (c'est le pro qui l'ajoute).
  Future<void> _ajouterParticipantManuel() async {
    final nomCtrl = TextEditingController();
    final telCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ajouter un participant', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          Text('Pour un client qui n\'utilise pas l\'application (appel téléphonique).',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          TextField(controller: nomCtrl, autofocus: true, style: const TextStyle(fontFamily: 'Galey'),
              decoration: const InputDecoration(labelText: 'Nom', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: telCtrl, keyboardType: TextInputType.phone, style: const TextStyle(fontFamily: 'Galey'),
              decoration: const InputDecoration(labelText: 'Téléphone (optionnel)', border: OutlineInputBorder())),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _kEducationPurple, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
          )),
        ]),
      ),
    );
    if (ok != true || nomCtrl.text.trim().isEmpty) return;
    await _supa.from('cours_collectifs_participants').insert({
      'cours_id': widget.coursId,
      'client_nom_manuel': nomCtrl.text.trim(),
      if (telCtrl.text.trim().isNotEmpty) 'client_telephone_manuel': telCtrl.text.trim(),
      'statut': 'inscrit',
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final titre = _cours?['titre']?.toString() ?? 'Cours collectif';
    final capacite = _cours?['capacite_max'] as int? ?? 0;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _kEducationPurple,
        foregroundColor: Colors.white,
        title: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Ajouter un participant',
            onPressed: _ajouterParticipantManuel,
          ),
          if (_cours?['serie_id'] != null)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'serie' ? _cancelSerie() : _cancelCours(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'cours', child: Text('Annuler ce cours')),
                PopupMenuItem(value: 'serie', child: Text('Annuler toute la série')),
              ],
              icon: const Icon(Icons.cancel_outlined),
            )
          else
            IconButton(icon: const Icon(Icons.cancel_outlined), tooltip: 'Annuler le cours', onPressed: _cancelCours),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kEducationPurple))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Builder(builder: (_) {
                  final enAttente = _participants.where((p) => p['statut'] == 'en_attente').length;
                  final demandes = _participants.where((p) => p['statut'] == 'demande').length;
                  final inscrits = _participants.length - enAttente - demandes;
                  return Text(
                    '$inscrits / $capacite inscrits'
                        '${demandes > 0 ? ' · $demandes en attente de confirmation' : ''}'
                        '${enAttente > 0 ? ' · $enAttente en liste d\'attente' : ''}',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15),
                  );
                }),
                const SizedBox(height: 12),
                if (_participants.isEmpty)
                  Text('Aucun participant inscrit pour l\'instant.',
                      style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500))
                else
                  for (final p in _participants)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p['_client_nom'] as String, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                          if ((p['_animal_nom'] as String).isNotEmpty)
                            Text(p['_animal_nom'] as String, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
                        ])),
                        if (p['animal_id'] != null)
                          IconButton(
                            icon: const Icon(Icons.school_outlined, size: 20, color: _kEducationPurple),
                            tooltip: 'Ajouter un rapport',
                            onPressed: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => AnimalFichePage(
                                animalId: p['animal_id'].toString(),
                                readOnly: true,
                                educationMode: true,
                                initialTabIndex: 2,
                              ),
                            )),
                          ),
                        if (p['statut'] == 'demande') ...[
                          TextButton(
                            onPressed: () => _confirmerDemande(p['id'] as String),
                            style: TextButton.styleFrom(foregroundColor: const Color(0xFF6E9E57), padding: const EdgeInsets.symmetric(horizontal: 8)),
                            child: const Text('Confirmer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                          TextButton(
                            onPressed: () => _updateStatut(p['id'] as String, 'annule'),
                            style: TextButton.styleFrom(foregroundColor: Colors.red.shade400, padding: const EdgeInsets.symmetric(horizontal: 8)),
                            child: const Text('Refuser', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        ] else
                          PopupMenuButton<String>(
                            onSelected: (v) => _updateStatut(p['id'] as String, v),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'present', child: Text('Présent')),
                              PopupMenuItem(value: 'absent', child: Text('Absent')),
                              PopupMenuItem(value: 'annule', child: Text('Retirer')),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: p['statut'] == 'present' ? const Color(0xFFEEF5EA)
                                    : p['statut'] == 'absent' ? Colors.red.shade50
                                    : p['statut'] == 'en_attente' ? Colors.orange.shade50 : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(p['statut'] == 'en_attente' ? 'en attente' : (p['statut'] as String? ?? 'inscrit'),
                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                            ),
                          ),
                      ]),
                    ),
              ],
            ),
    );
  }
}

// ── Détail d'un RDV individuel (depuis le planning) ───────────────────────────
// Infos + message du client + coordonnées propriétaire + fiche animal en
// lecture. La confirmation/refus se fait dans l'agenda (flux complet :
// agenda_events, accès carnet, notifications).
class _RdvDetailSheet extends StatelessWidget {
  final Map<String, dynamic> rdv;
  const _RdvDetailSheet({required this.rdv});

  @override
  Widget build(BuildContext context) {
    final d = DateTime.tryParse(rdv['date_heure']?.toString() ?? '')?.toLocal();
    final dateStr = d != null ? DateFormat('EEEE d MMMM · HH:mm', 'fr_FR').format(d) : '';
    final clientNom = (rdv['_client_nom']?.toString() ?? 'Client').trim();
    final animalNom = (rdv['_animal_nom']?.toString() ?? '').trim();
    final motif = rdv['motif']?.toString() ?? 'Cours';
    final message = rdv['notes_client']?.toString().trim() ?? '';
    final animalId = rdv['animal_id']?.toString();
    final statut = rdv['statut']?.toString() ?? '';
    final telManuel = rdv['client_telephone_manuel']?.toString().trim() ?? '';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        Text(motif, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 16)),
        if (dateStr.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(dateStr, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade600)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.person_outline, size: 16, color: _kEducationTeal),
          const SizedBox(width: 8),
          Expanded(child: Text(clientNom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13.5))),
        ]),
        if (animalNom.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.pets, size: 15, color: Color(0xFF6E9E57)),
            const SizedBox(width: 8),
            Text(animalNom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF6E9E57))),
          ]),
        ],
        if ((rdv['lieu']?.toString().trim().isNotEmpty ?? false)) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.place_outlined, size: 15, color: _kEducationTeal),
            const SizedBox(width: 8),
            Expanded(child: Text(rdv['lieu'].toString(), style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
            GestureDetector(
              onTap: () {
                final lat = rdv['lieu_lat'], lng = rdv['lieu_lng'];
                final q = (lat != null && lng != null) ? '$lat,$lng' : Uri.encodeComponent(rdv['lieu'].toString());
                launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'), mode: LaunchMode.externalApplication);
              },
              child: const Text('Itinéraire', style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: _kEducationTeal)),
            ),
          ]),
        ],
        if (message.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0x0C0C5C6C),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x260C5C6C)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Message du client', style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: _kEducationTeal)),
              const SizedBox(height: 4),
              Text(message, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF37474F))),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          if ((rdv['client_uid']?.toString().isNotEmpty ?? false) && animalId != null && animalId.isNotEmpty)
            _ActionChip(
              icon: Icons.contact_phone_outlined,
              label: 'Coordonnées',
              child: OwnerContactButton(
                animalId: animalId,
                animalNom: animalNom.isNotEmpty ? animalNom : clientNom,
                ownerUid: rdv['client_uid']?.toString(),
                size: 18,
              ),
            )
          else if (telManuel.isNotEmpty)
            ActionChipButton(
              icon: Icons.call_outlined, label: telManuel,
              onTap: () => launchUrl(Uri(scheme: 'tel', path: telManuel.replaceAll(RegExp(r'[^0-9+]'), '')),
                  mode: LaunchMode.externalApplication),
            ),
          if (animalId != null && animalId.isNotEmpty)
            ActionChipButton(
              icon: Icons.pets_outlined, label: 'Fiche de l\'animal',
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => AnimalFichePage(animalId: animalId, readOnly: true, educationMode: true, rdvId: rdv['id']?.toString()),
              )),
            ),
        ]),
        if (statut == 'demande') ...[
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProAgendaPage(initialTabIndex: 0)));
            },
            style: ElevatedButton.styleFrom(backgroundColor: _kEducationPurple, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13)),
            icon: const Icon(Icons.event_available_outlined, size: 18),
            label: const Text('Confirmer / refuser dans l\'agenda', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          )),
        ],
      ]),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;
  const _ActionChip({required this.icon, required this.label, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(left: 4, right: 10),
    decoration: BoxDecoration(
      color: const Color(0x0C0C5C6C),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0x260C5C6C)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      child,
      Text(label, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12.5, color: _kEducationTeal)),
    ]),
  );
}

class ActionChipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const ActionChipButton({super.key, required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x0C0C5C6C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x260C5C6C)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: _kEducationTeal),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12.5, color: _kEducationTeal)),
      ]),
    ),
  );
}
