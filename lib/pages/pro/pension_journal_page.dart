import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/storage_helper.dart' as storage;

class PensionJournalPage extends StatefulWidget {
  final String? animalId;
  final String? pensionEntreeId;
  final String animalNom;
  final bool readOnly; // true côté propriétaire (lecture seule)

  const PensionJournalPage({
    super.key,
    this.animalId,
    this.pensionEntreeId,
    required this.animalNom,
    this.readOnly = false,
  });

  @override
  State<PensionJournalPage> createState() => _PensionJournalPageState();
}

class _PensionJournalPageState extends State<PensionJournalPage> {
  final _supa = Supabase.instance.client;
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  List<Map<String, dynamic>> _updates = [];
  bool _loading = true;
  bool _posting = false;
  File? _photoFile;
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      dynamic q = _supa.from('pension_updates').select();
      if (widget.pensionEntreeId != null) {
        q = q.eq('pension_entree_id', widget.pensionEntreeId!);
      } else if (widget.animalId != null) {
        q = q.eq('animal_id', widget.animalId!);
      } else {
        setState(() { _updates = []; _loading = false; });
        return;
      }
      final rows = await q.order('created_at', ascending: false);
      if (mounted) setState(() { _updates = List<Map<String, dynamic>>.from(rows as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    setState(() => _photoFile = File(file.path));
  }

  Future<void> _post() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_photoFile == null && _noteCtrl.text.trim().isEmpty) return;
    setState(() => _posting = true);
    try {
      String? photoUrl;
      if (_photoFile != null) {
        final path = 'pension_updates/${uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        photoUrl = await storage.uploadPhoto(_photoFile!, path, quality: 75);
      }
      await _supa.from('pension_updates').insert({
        'pension_entree_id': widget.pensionEntreeId,
        'animal_id':         widget.animalId,
        'pro_uid':            uid,
        'photo_url':          photoUrl,
        'note':               _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      });
      _photoFile = null;
      _noteCtrl.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _delete(String id) async {
    await _supa.from('pension_updates').delete().eq('id', id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text('Journal — ${widget.animalNom}', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _teal))
              : _updates.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.photo_camera_back_outlined, size: 60, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(widget.readOnly ? 'Aucune nouvelle pour l\'instant' : 'Partagez une première nouvelle',
                          style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
                    ]))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      itemCount: _updates.length,
                      itemBuilder: (_, i) {
                        final u = _updates[i];
                        final date = DateTime.tryParse(u['created_at']?.toString() ?? '');
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (u['photo_url'] != null)
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                child: Image.network(u['photo_url'] as String, width: double.infinity, height: 220, fit: BoxFit.cover),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                if (u['note'] != null && (u['note'] as String).isNotEmpty)
                                  Text(u['note'] as String, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
                                const SizedBox(height: 6),
                                Row(children: [
                                  Text(date != null ? DateFormat('dd/MM/yyyy à HH:mm').format(date) : '',
                                      style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade400)),
                                  if (!widget.readOnly) ...[
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                      onPressed: () => _delete(u['id'] as String),
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ],
                                ]),
                              ]),
                            ),
                          ]),
                        );
                      },
                    ),
        ),
        if (!widget.readOnly)
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
            decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade200))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_photoFile != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Stack(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(10),
                        child: Image.file(_photoFile!, height: 80, width: 80, fit: BoxFit.cover)),
                    Positioned(top: 2, right: 2, child: GestureDetector(
                      onTap: () => setState(() => _photoFile = null),
                      child: const CircleAvatar(radius: 10, backgroundColor: Colors.black54,
                          child: Icon(Icons.close, size: 12, color: Colors.white)),
                    )),
                  ]),
                ),
              Row(children: [
                IconButton(icon: const Icon(Icons.photo_camera_outlined, color: _teal), onPressed: _pickPhoto),
                Expanded(
                  child: TextField(
                    controller: _noteCtrl,
                    minLines: 1, maxLines: 3,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Une petite note pour le propriétaire…',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: _posting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _green))
                      : const Icon(Icons.send_rounded, color: _green),
                  onPressed: _posting ? null : _post,
                ),
              ]),
            ]),
          ),
      ]),
    );
  }
}
