import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';

const _kEducationTeal = Color(0xFF0C5C6C);
const _kEducationPurple = Color(0xFF7B5EA7);

class EducationPlanningPage extends StatefulWidget {
  const EducationPlanningPage({super.key});
  @override
  State<EducationPlanningPage> createState() => _EducationPlanningPageState();
}

class _EducationPlanningPageState extends State<EducationPlanningPage> {
  final _supa = Supabase.instance.client;

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
      if (mounted) {
        setState(() {
          _rdvs = List<Map<String, dynamic>>.from(results[0] as List);
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
    final sousTitre = isCours
        ? '${_participantsCount[s['id']] ?? 0} / ${s['capacite_max']} inscrits'
        : 'Individuel — ${s['duree_minutes'] ?? 60} min';

    return GestureDetector(
      onTap: isCours ? () => _openCours(s) : null,
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
            Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
            Text(sousTitre, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          ])),
          if (isCours) Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
        ]),
      ),
    );
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
      final titre = _titreCtrl.text.trim();
      final inserted = await _supa.from('cours_collectifs').insert({
        'pro_uid': uid,
        'pro_profile_id': User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
        'titre': titre,
        'date_heure': dateHeure.toIso8601String(),
        'duree_minutes': dureeMinutes,
        'capacite_max': int.tryParse(_capaciteCtrl.text.trim()) ?? 6,
        'lieu': _lieuCtrl.text.trim().isEmpty ? null : _lieuCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      }).select('id').single();
      // Visible dans "Mon agenda" (même mécanisme que les RDV confirmés).
      try {
        await _supa.from('agenda_events').insert({
          'uid': uid,
          'titre': '👥 $titre',
          'type': 'cours_collectif',
          'date_debut': dateHeure.toIso8601String(),
          'duree_minutes': dureeMinutes,
          'couleur': 'cours:${inserted['id']}',
          'pro_profile_id': User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
        });
      } catch (_) {}
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
      final clientUids = list.map((p) => p['client_uid'] as String).toSet().toList();
      final animalIds = list.map((p) => p['animal_id']?.toString()).whereType<String>().toList();
      final names = <String, String>{};
      final animalNames = <String, String>{};
      if (clientUids.isNotEmpty) {
        final users = await _supa.from('users').select('uid, firstname, lastname').inFilter('uid', clientUids);
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
        p['_client_nom'] = names[p['client_uid']]?.isNotEmpty == true ? names[p['client_uid']] : 'Client';
        p['_animal_nom'] = animalNames[p['animal_id']?.toString()] ?? '';
      }
      if (mounted) setState(() { _cours = cours; _participants = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateStatut(String participantId, String statut) async {
    await _supa.from('cours_collectifs_participants').update({'statut': statut}).eq('id', participantId);
    _load();
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
          IconButton(icon: const Icon(Icons.cancel_outlined), tooltip: 'Annuler le cours', onPressed: _cancelCours),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kEducationPurple))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('${_participants.length} / $capacite inscrits',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
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
                                  : p['statut'] == 'absent' ? Colors.red.shade50 : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(p['statut'] as String? ?? 'inscrit',
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
