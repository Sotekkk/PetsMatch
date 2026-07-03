import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/services/plan_service.dart';
import 'package:PetsMatch/pages/pro/pension_abonnement_page.dart';

class PensionChenilPage extends StatefulWidget {
  const PensionChenilPage({super.key});
  @override
  State<PensionChenilPage> createState() => _PensionChenilPageState();
}

class _PensionChenilPageState extends State<PensionChenilPage> {
  final _supa = Supabase.instance.client;
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  List<Map<String, dynamic>> _logements = [];
  List<Map<String, dynamic>> _entrees = [];
  bool _loading = true;
  String? _uid;
  String _planCode = 'free';

  static const _types = [
    ('box', 'Box'),
    ('enclos', 'Enclos'),
    ('parc', 'Parc'),
    ('chatterie', 'Chatterie'),
    ('cage', 'Cage'),
  ];
  static const _typeLabels = {'box': 'Box', 'enclos': 'Enclos', 'parc': 'Parc', 'chatterie': 'Chatterie', 'cage': 'Cage'};

  @override
  void initState() {
    super.initState();
    _load();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final code = await PlanService.getPensionPlanCode(uid);
    if (mounted) setState(() => _planCode = code);
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _uid = uid;
    try {
      final results = await Future.wait([
        _supa.from('enclos_chenil').select().eq('uid_eleveur', uid).order('nom'),
        _supa.from('pension_entrees').select().eq('pro_uid', uid).eq('statut', 'en_pension').order('date_entree'),
      ]);
      if (mounted) {
        setState(() {
          _logements = List<Map<String, dynamic>>.from(results[0] as List);
          _entrees   = List<Map<String, dynamic>>.from(results[1] as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _occupants(String logementId) =>
      _entrees.where((e) => e['logement_id'] == logementId).toList();

  List<Map<String, dynamic>> get _nonAssignes =>
      _entrees.where((e) => e['logement_id'] == null).toList();

  Future<void> _saveLogement({String? id, required String nom, required String type, required int capacite, String? notes}) async {
    if (_uid == null) return;
    final payload = {
      'uid_eleveur': _uid,
      'nom': nom,
      'type': type,
      'capacite': capacite,
      'notes': notes?.isEmpty == true ? null : notes,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (id != null) {
      await _supa.from('enclos_chenil').update(payload).eq('id', id);
    } else {
      await _supa.from('enclos_chenil').insert(payload);
    }
    _load();
  }

  Future<void> _deleteLogement(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer ce logement ?', style: TextStyle(fontFamily: 'Galey')),
        content: const Text('Les animaux qui y sont assignés seront libérés.', style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await _supa.from('enclos_chenil').delete().eq('id', id);
      _load();
    }
  }

  Future<void> _assign(String entreeId, String? logementId) async {
    await _supa.from('pension_entrees').update({'logement_id': logementId}).eq('id', entreeId);
    _load();
  }

  void _showLogementSheet({Map<String, dynamic>? logement}) {
    if (logement == null && _planCode == 'free' && _logements.isNotEmpty) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PensionAbonnementPage()));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('La formule Découverte est limitée à 1 logement — passez en formule Pro pour en ajouter davantage.',
            style: TextStyle(fontFamily: 'Galey')),
      ));
      return;
    }
    final nomCtrl = TextEditingController(text: logement?['nom'] as String? ?? '');
    final capaciteCtrl = TextEditingController(text: (logement?['capacite'] ?? 1).toString());
    final notesCtrl = TextEditingController(text: logement?['notes'] as String? ?? '');
    String type = logement?['type'] as String? ?? 'box';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(logement != null ? 'Modifier le logement' : 'Ajouter un logement',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 12),
            TextField(controller: nomCtrl, decoration: const InputDecoration(labelText: 'Nom (ex : Box 3)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: _types.map((t) {
              final active = type == t.$1;
              return GestureDetector(
                onTap: () => setSheet(() => type = t.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: active ? _teal : Colors.white,
                    border: Border.all(color: active ? _teal : Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(t.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                      color: active ? Colors.white : Colors.black87)),
                ),
              );
            }).toList()),
            const SizedBox(height: 12),
            TextField(controller: capaciteCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Capacité (nb d\'animaux)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: notesCtrl, maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes (optionnel)', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final nom = nomCtrl.text.trim();
                  if (nom.isEmpty) return;
                  Navigator.pop(ctx);
                  _saveLogement(
                    id: logement?['id'] as String?,
                    nom: nom,
                    type: type,
                    capacite: int.tryParse(capaciteCtrl.text.trim()) ?? 1,
                    notes: notesCtrl.text.trim(),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text(logement != null ? 'Enregistrer' : 'Ajouter',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showAssignSheet(Map<String, dynamic> logement) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Assigner à ${logement['nom']}',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          if (_nonAssignes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('Aucun animal en pension non assigné.', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _nonAssignes.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final e = _nonAssignes[i];
                  return ListTile(
                    title: Text(e['animal_nom'] as String? ?? '?',
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                    subtitle: Text(e['espece'] as String? ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                    trailing: ElevatedButton(
                      onPressed: () { Navigator.pop(context); _assign(e['id'] as String, logement['id'] as String); },
                      style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white),
                      child: const Text('Placer', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                    ),
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Logements / Chenil', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showLogementSheet(),
        backgroundColor: _teal,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _logements.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 80),
                      Center(child: Column(children: [
                        Icon(Icons.home_work_outlined, size: 60, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('Aucun logement enregistré', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
                        const SizedBox(height: 4),
                        Text('Créez vos box, enclos ou chatterie pour suivre l\'occupation.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
                      ])),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      itemCount: _logements.length,
                      itemBuilder: (_, i) {
                        final l = _logements[i];
                        final occ = _occupants(l['id'] as String);
                        final capacite = (l['capacite'] as int?) ?? 1;
                        final dispo = capacite - occ.length;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
                          ),
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: _teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: Text(_typeLabels[l['type']] ?? l['type']?.toString() ?? '',
                                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600, color: _teal)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(l['nom'] as String? ?? '',
                                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15))),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: dispo > 0 ? _green.withValues(alpha: 0.12) : Colors.orange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('${occ.length}/$capacite',
                                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12,
                                        color: dispo > 0 ? _green : Colors.orange)),
                              ),
                              IconButton(icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
                                  onPressed: () => _showLogementSheet(logement: l)),
                              IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                  onPressed: () => _deleteLogement(l['id'] as String)),
                            ]),
                            if (occ.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(spacing: 6, runSpacing: 4, children: occ.map((e) => GestureDetector(
                                onTap: () => _assign(e['id'] as String, null),
                                child: Chip(
                                  label: Text('${e['animal_nom'] ?? '?'} ✕', style: const TextStyle(fontFamily: 'Galey', fontSize: 11)),
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: _teal.withValues(alpha: 0.08),
                                ),
                              )).toList()),
                            ],
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: dispo > 0 ? () => _showAssignSheet(l) : null,
                                icon: const Icon(Icons.pets, size: 14),
                                label: const Text('Assigner un animal', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                                style: OutlinedButton.styleFrom(foregroundColor: _green,
                                    side: BorderSide(color: _green.withValues(alpha: 0.5))),
                              ),
                            ),
                          ]),
                        );
                      },
                    ),
            ),
    );
  }
}
