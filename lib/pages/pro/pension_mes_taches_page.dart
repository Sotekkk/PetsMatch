import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart';

/// "Mes tâches" pour la pension — liste simple des tâches assignées au
/// pro (taches_elevage, profil_source='pension'), même fonctionnalité que
/// /mes-taches sur le site web.
class PensionMesTachesPage extends StatefulWidget {
  const PensionMesTachesPage({super.key});

  @override
  State<PensionMesTachesPage> createState() => _PensionMesTachesPageState();
}

class _PensionMesTachesPageState extends State<PensionMesTachesPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _bg    = Color(0xFFF8F8F6);

  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _taches = [];
  List<({String uid, String? profileId, String nom})> _equipe = [];
  List<Map<String, dynamic>> _pensionnaires = [];
  bool _loading = true;
  bool _showDone = false;
  String? _toggling;

  @override
  void initState() {
    super.initState();
    _load();
    _loadEquipeEtPensionnaires();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final pid = User_Info.activeProfileId;
      var q = _supa.from('taches_elevage').select().eq('profil_source', 'pension');
      q = pid.isNotEmpty ? q.eq('assigne_profile_id', pid) : q.eq('assigne_a', _uid);
      final rows = await q.order('date', ascending: true);
      if (mounted) {
        setState(() {
          _taches = List<Map<String, dynamic>>.from(rows as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadEquipeEtPensionnaires() async {
    final uid = _uid;
    if (uid.isEmpty) return;
    try {
      final pid = User_Info.activeProfileId;
      final equipe = <({String uid, String? profileId, String nom})>[
        (uid: uid, profileId: pid.isNotEmpty ? pid : null, nom: 'Moi'),
      ];
      var qEmp = _supa.from('employes').select('uid_employe, employe_profile_id, prenom, nom').eq('actif', true);
      qEmp = pid.isNotEmpty ? qEmp.eq('eleveur_profile_id', pid) : qEmp.eq('uid_eleveur', uid);
      final emps = await qEmp;
      for (final e in emps as List) {
        final nom = '${e['prenom'] ?? ''} ${e['nom'] ?? ''}'.trim();
        equipe.add((
          uid: e['uid_employe'] as String,
          profileId: e['employe_profile_id'] as String?,
          nom: nom.isNotEmpty ? nom : 'Employé',
        ));
      }

      final pensionnaires = await _supa.from('pension_entrees')
          .select('id, animal_nom')
          .eq('pro_uid', uid).eq('statut', 'en_pension').order('animal_nom');

      if (mounted) {
        setState(() {
          _equipe = equipe;
          _pensionnaires = List<Map<String, dynamic>>.from(pensionnaires as List);
        });
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _filtered =>
      _showDone ? _taches : _taches.where((t) => t['statut'] != 'fait').toList();

  Future<void> _toggleFait(Map<String, dynamic> t) async {
    if (_toggling != null) return;
    final id = t['id'].toString();
    final newStatut = t['statut'] == 'fait' ? 'a_faire' : 'fait';
    setState(() { _toggling = id; t['statut'] = newStatut; });
    try {
      await _supa.from('taches_elevage').update({'statut': newStatut}).eq('id', id);
    } catch (_) {}
    if (mounted) setState(() => _toggling = null);
  }

  static String _fmtDate(String? s) {
    if (s == null || s.isEmpty) return '—';
    final d = DateTime.tryParse(s);
    return d != null ? DateFormat('dd/MM/yyyy', 'fr').format(d) : s;
  }

  void _openAddSheet() {
    final titreCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime date = DateTime.now();
    String? animalId;
    var assignee = _equipe.isNotEmpty ? _equipe.first : null;
    bool saving = false;
    String? error;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const Text('Nouvelle tâche',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(height: 16),
              TextField(
                controller: titreCtrl,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Titre *',
                  labelStyle: const TextStyle(fontFamily: 'Galey'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (c, child) => Theme(
                      data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: _teal)),
                      child: child!,
                    ),
                  );
                  if (picked != null) setModal(() => date = picked);
                },
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(DateFormat('dd/MM/yyyy', 'fr').format(date),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _teal, side: const BorderSide(color: _teal),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              if (_pensionnaires.isNotEmpty) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: animalId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Animal (optionnel)',
                    labelStyle: const TextStyle(fontFamily: 'Galey'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1F2A2E)),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Aucun')),
                    for (final p in _pensionnaires)
                      DropdownMenuItem<String?>(value: p['id'] as String, child: Text(p['animal_nom'] as String? ?? '')),
                  ],
                  onChanged: (v) => setModal(() => animalId = v),
                ),
              ],
              if (_equipe.length > 1) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<({String uid, String? profileId, String nom})>(
                  initialValue: assignee,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Assignée à',
                    labelStyle: const TextStyle(fontFamily: 'Galey'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1F2A2E)),
                  items: [
                    for (final e in _equipe) DropdownMenuItem(value: e, child: Text(e.nom)),
                  ],
                  onChanged: (v) => setModal(() => assignee = v),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Notes (optionnel)',
                  labelStyle: const TextStyle(fontFamily: 'Galey'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.red)),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: saving ? null : () async {
                    if (titreCtrl.text.trim().isEmpty) {
                      setModal(() => error = 'Le titre est requis.');
                      return;
                    }
                    setModal(() { saving = true; error = null; });
                    final ok = await _creerTache(
                      titre: titreCtrl.text.trim(),
                      date: date,
                      animalId: animalId,
                      animalNom: animalId != null
                          ? _pensionnaires.firstWhere((p) => p['id'] == animalId)['animal_nom'] as String?
                          : null,
                      assigneUid: assignee?.uid,
                      assigneProfileId: assignee?.profileId,
                      notes: notesCtrl.text.trim(),
                    );
                    if (ok && ctx.mounted) Navigator.pop(ctx);
                    else setModal(() { saving = false; error = 'Erreur lors de la création.'; });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: saving
                      ? const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Créer la tâche',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<bool> _creerTache({
    required String titre,
    required DateTime date,
    String? animalId,
    String? animalNom,
    String? assigneUid,
    String? assigneProfileId,
    required String notes,
  }) async {
    final uid = _uid;
    if (uid.isEmpty) return false;
    final pid = User_Info.activeProfileId;
    try {
      await _supa.from('taches_elevage').insert({
        'uid_eleveur':    uid,
        'titre':          titre,
        'date':           DateFormat('yyyy-MM-dd').format(date),
        'statut':         'a_faire',
        'profil_source':  'pension',
        if (pid.isNotEmpty) 'eleveur_profile_id': pid,
        if (pid.isNotEmpty) 'profile_id': pid,
        'animal_id':      animalId,
        'animal_nom':     animalNom,
        'assigne_a':      assigneUid ?? uid,
        if (assigneProfileId != null) 'assigne_profile_id': assigneProfileId,
        if (notes.isNotEmpty) 'notes': notes,
      });
      await _load();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Mes tâches',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: Icon(_showDone ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            tooltip: _showDone ? 'Masquer les terminées' : 'Voir les terminées',
            onPressed: () => setState(() => _showDone = !_showDone),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: _load,
              color: _teal,
              child: _filtered.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 100),
                      Center(child: Text('Aucune tâche', style: TextStyle(fontFamily: 'Galey', color: Colors.grey))),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final t = _filtered[i];
                        final done = t['statut'] == 'fait';
                        final animalNom = t['animal_nom'] as String?;
                        final notes = t['notes'] as String?;
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            GestureDetector(
                              onTap: () => _toggleFait(t),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 22, height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: done ? _green : Colors.white,
                                  border: Border.all(color: done ? _green : Colors.grey.shade400, width: 2),
                                ),
                                child: done ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(t['titre'] as String? ?? '',
                                    style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600,
                                        color: done ? Colors.grey : const Color(0xFF1F2A2E),
                                        decoration: done ? TextDecoration.lineThrough : null)),
                                const SizedBox(height: 2),
                                Text(
                                  [_fmtDate(t['date'] as String?), if (animalNom?.isNotEmpty == true) animalNom!].join(' · '),
                                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500),
                                ),
                                if (notes?.isNotEmpty == true) ...[
                                  const SizedBox(height: 4),
                                  Text(notes!,
                                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                                ],
                              ]),
                            ),
                          ]),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _teal,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: Colors.white)),
        onPressed: _openAddSheet,
      ),
    );
  }
}
