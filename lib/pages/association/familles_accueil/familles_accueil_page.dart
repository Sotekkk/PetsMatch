import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FamillesAccueilPage extends StatefulWidget {
  const FamillesAccueilPage({super.key});
  @override
  State<FamillesAccueilPage> createState() => _FamillesAccueilPageState();
}

class _FamillesAccueilPageState extends State<FamillesAccueilPage> {
  final _supa = Supabase.instance.client;

  static const _teal = Color(0xFF0C5C6C);
  static const _purple = Colors.purple;

  List<Map<String, dynamic>> _fa = [];
  bool _loading = true;

  final _prenomCtrl = TextEditingController();
  final _nomCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _adresseCtrl = TextEditingController();
  final _villeCtrl = TextEditingController();
  final _cpCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  int _capaciteMax = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _prenomCtrl.dispose();
    _nomCtrl.dispose();
    _emailCtrl.dispose();
    _telCtrl.dispose();
    _adresseCtrl.dispose();
    _villeCtrl.dispose();
    _cpCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final data = await _supa
          .from('familles_accueil')
          .select('*, animaux(id, nom, photo_url, statut)')
          .eq('association_uid', uid)
          .eq('actif', true)
          .order('nom');
      if (mounted) {
        setState(() {
          _fa = List<Map<String, dynamic>>.from(data as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addFa() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_prenomCtrl.text.trim().isEmpty || _nomCtrl.text.trim().isEmpty) return;

    try {
      await _supa.from('familles_accueil').insert({
        'association_uid': uid,
        'prenom': _prenomCtrl.text.trim(),
        'nom': _nomCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'telephone': _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        'adresse': _adresseCtrl.text.trim().isEmpty ? null : _adresseCtrl.text.trim(),
        'ville': _villeCtrl.text.trim().isEmpty ? null : _villeCtrl.text.trim(),
        'code_postal': _cpCtrl.text.trim().isEmpty ? null : _cpCtrl.text.trim(),
        'capacite_max': _capaciteMax,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'actif': true,
      });
      _clearForm();
      if (mounted) Navigator.pop(context);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _clearForm() {
    _prenomCtrl.clear();
    _nomCtrl.clear();
    _emailCtrl.clear();
    _telCtrl.clear();
    _adresseCtrl.clear();
    _villeCtrl.clear();
    _cpCtrl.clear();
    _notesCtrl.clear();
    _capaciteMax = 1;
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer la FA', style: TextStyle(fontFamily: 'Galey')),
        content: const Text('Cette action est irréversible.', style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _supa.from('familles_accueil').update({'actif': false}).eq('id', id);
      _load();
    }
  }

  void _showAddSheet() {
    setState(() => _capaciteMax = 1);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ajouter une famille d\'accueil',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _field(_prenomCtrl, 'Prénom *')),
                    const SizedBox(width: 10),
                    Expanded(child: _field(_nomCtrl, 'Nom *')),
                  ],
                ),
                const SizedBox(height: 10),
                _field(_emailCtrl, 'Email', keyboard: TextInputType.emailAddress),
                const SizedBox(height: 10),
                _field(_telCtrl, 'Téléphone', keyboard: TextInputType.phone),
                const SizedBox(height: 10),
                _field(_adresseCtrl, 'Adresse'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _field(_villeCtrl, 'Ville')),
                    const SizedBox(width: 10),
                    Expanded(child: _field(_cpCtrl, 'Code postal', keyboard: TextInputType.number)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Capacité max :', style: TextStyle(fontFamily: 'Galey')),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => setInner(() { if (_capaciteMax > 1) _capaciteMax--; }),
                    ),
                    Text('$_capaciteMax', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setInner(() => _capaciteMax++),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _field(_notesCtrl, 'Notes (espèces, contraintes…)', maxLines: 2),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _addFa,
                    style: ElevatedButton.styleFrom(backgroundColor: _teal),
                    child: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, {TextInputType? keyboard, int maxLines = 1}) =>
      TextField(
        controller: ctrl,
        keyboardType: keyboard,
        maxLines: maxLines,
        style: const TextStyle(fontFamily: 'Galey'),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        title: const Text('Familles d\'accueil',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        backgroundColor: _teal,
        icon: const Icon(Icons.house_outlined, color: Colors.white),
        label: const Text('Ajouter une FA', style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _fa.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.house_outlined, size: 60, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      const Text('Aucune famille d\'accueil',
                          style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _showAddSheet,
                        icon: const Icon(Icons.add),
                        label: const Text('Ajouter une FA', style: TextStyle(fontFamily: 'Galey')),
                        style: ElevatedButton.styleFrom(backgroundColor: _teal),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  itemCount: _fa.length,
                  itemBuilder: (_, i) {
                    final f = _fa[i];
                    final animaux = (f['animaux'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                    final capacite = f['capacite_max'] ?? 1;
                    final dispo = capacite - animaux.length;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: _teal,
                                  child: Text(
                                    (f['prenom']?.toString() ?? '?')[0].toUpperCase(),
                                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${f['prenom'] ?? ''} ${f['nom'] ?? ''}',
                                          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                                      if (f['ville'] != null)
                                        Text(f['ville'], style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: dispo > 0 ? const Color(0xFF6E9E57).withValues(alpha: 0.12) : Colors.orange.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text('${animaux.length}/$capacite',
                                      style: TextStyle(
                                          fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 12,
                                          color: dispo > 0 ? const Color(0xFF6E9E57) : Colors.orange)),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                  onPressed: () => _delete(f['id']),
                                ),
                              ],
                            ),
                            if (f['email'] != null || f['telephone'] != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  if (f['email'] != null) ...[
                                    const Icon(Icons.email_outlined, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(f['email'], style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                                    const SizedBox(width: 12),
                                  ],
                                  if (f['telephone'] != null) ...[
                                    const Icon(Icons.phone_outlined, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(f['telephone'], style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                                  ],
                                ],
                              ),
                            ],
                            if (animaux.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              const Text('Animaux en accueil :',
                                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0C5C6C))),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                children: animaux.map((a) => Chip(
                                  label: Text(a['nom'] ?? '?',
                                      style: const TextStyle(fontFamily: 'Galey', fontSize: 11)),
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: const Color(0xFF0C5C6C).withValues(alpha: 0.08),
                                )).toList(),
                              ),
                            ],
                            if (f['notes'] != null) ...[
                              const SizedBox(height: 8),
                              Text(f['notes'],
                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey),
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
