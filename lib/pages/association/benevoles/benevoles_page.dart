import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BenevolesPage extends StatefulWidget {
  const BenevolesPage({super.key});
  @override
  State<BenevolesPage> createState() => _BenevolesPageState();
}

class _BenevolesPageState extends State<BenevolesPage> {
  final _supa = Supabase.instance.client;

  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  List<Map<String, dynamic>> _benevoles = [];
  bool _loading = true;

  final _prenomCtrl = TextEditingController();
  final _nomCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

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
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final data = await _supa
          .from('employes')
          .select()
          .eq('uid_eleveur', uid)
          .eq('type', 'benevole')
          .order('nom');
      if (mounted) {
        setState(() {
          _benevoles = List<Map<String, dynamic>>.from(data as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addBenevole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_prenomCtrl.text.trim().isEmpty || _nomCtrl.text.trim().isEmpty) return;

    try {
      await _supa.from('employes').insert({
        'uid_eleveur': uid,
        'prenom': _prenomCtrl.text.trim(),
        'nom': _nomCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'telephone': _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'actif': true,
        'type': 'benevole',
      });
      _prenomCtrl.clear();
      _nomCtrl.clear();
      _emailCtrl.clear();
      _telCtrl.clear();
      _notesCtrl.clear();
      if (mounted) Navigator.pop(context);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggle(String id, bool actif) async {
    await _supa.from('employes').update({'actif': !actif}).eq('id', id);
    _load();
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer le bénévole', style: TextStyle(fontFamily: 'Galey')),
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
      await _supa.from('employes').delete().eq('id', id);
      _load();
    }
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ajouter un bénévole',
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
            _field(_notesCtrl, 'Notes', maxLines: 2),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _addBenevole,
                style: ElevatedButton.styleFrom(backgroundColor: _teal),
                child: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              ),
            ),
          ],
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
    final actifs = _benevoles.where((b) => b['actif'] == true).toList();
    final inactifs = _benevoles.where((b) => b['actif'] != true).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        title: const Text('Bénévoles',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _showAddSheet),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        backgroundColor: _teal,
        icon: const Icon(Icons.person_add_outlined, color: Colors.white),
        label: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _benevoles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.volunteer_activism_outlined, size: 60, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      const Text('Aucun bénévole enregistré',
                          style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _showAddSheet,
                        icon: const Icon(Icons.add),
                        label: const Text('Ajouter un bénévole', style: TextStyle(fontFamily: 'Galey')),
                        style: ElevatedButton.styleFrom(backgroundColor: _teal),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (actifs.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text('Actifs (${actifs.length})',
                            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                fontSize: 14, color: _teal)),
                      ),
                      ...actifs.map((b) => _BenevoleTile(
                        benevole: b,
                        onToggle: () => _toggle(b['id'], b['actif'] == true),
                        onDelete: () => _delete(b['id']),
                      )),
                    ],
                    if (inactifs.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                        child: Text('Inactifs (${inactifs.length})',
                            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                fontSize: 14, color: Colors.grey)),
                      ),
                      ...inactifs.map((b) => _BenevoleTile(
                        benevole: b,
                        onToggle: () => _toggle(b['id'], b['actif'] == true),
                        onDelete: () => _delete(b['id']),
                      )),
                    ],
                  ],
                ),
    );
  }
}

class _BenevoleTile extends StatelessWidget {
  final Map<String, dynamic> benevole;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _BenevoleTile({required this.benevole, required this.onToggle, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final actif = benevole['actif'] == true;
    final prenom = benevole['prenom']?.toString() ?? '';
    final nom = benevole['nom']?.toString() ?? '';
    final email = benevole['email']?.toString() ?? '';
    final tel = benevole['telephone']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: actif ? const Color(0xFF0C5C6C) : Colors.grey.shade300,
          child: Text(
            prenom.isNotEmpty ? prenom[0].toUpperCase() : '?',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
        title: Text('$prenom $nom',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                color: actif ? const Color(0xFF1F2A2E) : Colors.grey)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (email.isNotEmpty)
              Text(email, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            if (tel.isNotEmpty)
              Text(tel, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(actif ? Icons.toggle_on : Icons.toggle_off,
                  color: actif ? const Color(0xFF6E9E57) : Colors.grey),
              onPressed: onToggle,
              tooltip: actif ? 'Désactiver' : 'Activer',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
