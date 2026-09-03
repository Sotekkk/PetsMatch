import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/storage_helper.dart' as storage;
import 'package:PetsMatch/pages/pro/education_shared.dart';

/// Bibliothèque d'exercices de l'éducateur : catalogue réutilisable
/// (titre + déroulé + photos/vidéos) qu'il attribue ensuite aux familles.
class EducationBibliothequePage extends StatefulWidget {
  /// Si non nul : mode sélection (retourne la liste d'exercices choisis).
  final bool pickMode;
  const EducationBibliothequePage({super.key, this.pickMode = false});

  @override
  State<EducationBibliothequePage> createState() => _EducationBibliothequePageState();
}

class _EducationBibliothequePageState extends State<EducationBibliothequePage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _exercices = [];
  final Set<String> _selected = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? User_Info.uid;
      final rows = await _supa.from('exercices_bibliotheque').select()
          .eq('pro_uid', uid).eq('actif', true).order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _exercices = List<Map<String, dynamic>>.from(rows as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _mediaOf(Map<String, dynamic> e) {
    final raw = e['media'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  Future<void> _edit([Map<String, dynamic>? existing]) async {
    final titreCtrl = TextEditingController(text: existing?['titre']?.toString() ?? '');
    final descCtrl = TextEditingController(text: existing?['description']?.toString() ?? '');
    String? categorie = existing?['categorie']?.toString();
    final media = existing != null ? _mediaOf(existing) : <Map<String, dynamic>>[];
    final newImages = <File>[];
    final newVideos = <File>[];
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 28),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              Text(existing == null ? 'Nouvel exercice' : 'Modifier l\'exercice',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 14),
              TextField(
                controller: titreCtrl,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Titre — ex : Le rappel au sifflet',
                  hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 4,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Déroulé : comment faire l\'exercice, matériel, durée, points d\'attention…',
                  hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: kEduCategories.entries.map((e) {
                final sel = categorie == e.key;
                return ChoiceChip(
                  label: Text(e.value, style: const TextStyle(fontFamily: 'Galey', fontSize: 11)),
                  selected: sel,
                  onSelected: (_) => setSheet(() => categorie = sel ? null : e.key),
                  selectedColor: kEduOrange.withValues(alpha: 0.18),
                  showCheckmark: false,
                );
              }).toList()),
              const SizedBox(height: 12),
              // Médias
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (int i = 0; i < media.length; i++)
                  _mediaThumb(
                    isVideo: media[i]['type'] == 'video',
                    imageWidget: media[i]['type'] == 'video'
                        ? null
                        : CachedNetworkImage(imageUrl: media[i]['url']?.toString() ?? '', fit: BoxFit.cover),
                    onRemove: () => setSheet(() => media.removeAt(i)),
                  ),
                for (int i = 0; i < newImages.length; i++)
                  _mediaThumb(imageWidget: Image.file(newImages[i], fit: BoxFit.cover),
                      onRemove: () => setSheet(() => newImages.removeAt(i))),
                for (int i = 0; i < newVideos.length; i++)
                  _mediaThumb(isVideo: true, onRemove: () => setSheet(() => newVideos.removeAt(i))),
                _addMediaBtn(Icons.add_photo_alternate_outlined, 'Photo', () async {
                  final f = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
                  if (f != null) setSheet(() => newImages.add(File(f.path)));
                }),
                _addMediaBtn(Icons.videocam_outlined, 'Vidéo', () async {
                  final f = await ImagePicker().pickVideo(source: ImageSource.gallery);
                  if (f == null) return;
                  if (await File(f.path).length() > 60 * 1024 * 1024) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('Vidéo trop lourde (max 60 Mo).', style: TextStyle(fontFamily: 'Galey'))));
                    }
                    return;
                  }
                  setSheet(() => newVideos.add(File(f.path)));
                }),
              ]),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: saving ? null : () async {
                  if (titreCtrl.text.trim().isEmpty) return;
                  setSheet(() => saving = true);
                  final uid = FirebaseAuth.instance.currentUser?.uid ?? User_Info.uid;
                  try {
                    for (final img in newImages) {
                      final url = await storage.uploadPhoto(img,
                          'exercices/$uid/${DateTime.now().microsecondsSinceEpoch}.jpg', quality: 78);
                      media.add({'type': 'image', 'url': url});
                    }
                    for (final vid in newVideos) {
                      final ext = vid.path.split('.').last.toLowerCase();
                      final url = await storage.uploadRawFile(vid,
                          'exercices/$uid/${DateTime.now().microsecondsSinceEpoch}.$ext');
                      media.add({'type': 'video', 'url': url});
                    }
                    final payload = {
                      'titre': titreCtrl.text.trim(),
                      'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                      'categorie': categorie,
                      'media': media,
                    };
                    if (existing == null) {
                      await _supa.from('exercices_bibliotheque').insert({
                        ...payload,
                        'pro_uid': uid,
                        if (User_Info.activeProfileId.isNotEmpty) 'pro_profile_id': User_Info.activeProfileId,
                      });
                    } else {
                      await _supa.from('exercices_bibliotheque').update(payload).eq('id', existing['id']);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _load();
                  } catch (e) {
                    setSheet(() => saving = false);
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kEduOrange, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              )),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _mediaThumb({Widget? imageWidget, bool isVideo = false, required VoidCallback onRemove}) {
    return Stack(children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: isVideo
            ? const Icon(Icons.play_circle_outline, color: Colors.grey)
            : (imageWidget ?? const SizedBox()),
      ),
      Positioned(right: 0, top: 0, child: GestureDetector(
        onTap: onRemove,
        child: Container(
          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
          child: const Icon(Icons.close, size: 14, color: Colors.white),
        ),
      )),
    ]);
  }

  Widget _addMediaBtn(IconData icon, String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18, color: Colors.grey.shade500),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 9, color: Colors.grey.shade500)),
          ]),
        ),
      );

  Future<void> _delete(Map<String, dynamic> e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer cet exercice de la bibliothèque ?', style: TextStyle(fontFamily: 'Galey')),
        content: const Text('Les exercices déjà attribués aux familles sont conservés.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Retirer', style: TextStyle(fontFamily: 'Galey', color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await _supa.from('exercices_bibliotheque').update({'actif': false}).eq('id', e['id']);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: kEduOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.pickMode ? 'Choisir des exercices' : 'Bibliothèque d\'exercices',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: widget.pickMode
          ? (_selected.isEmpty ? null : FloatingActionButton.extended(
              backgroundColor: kEduOrange, foregroundColor: Colors.white,
              onPressed: () => Navigator.pop(context,
                  _exercices.where((e) => _selected.contains(e['id'])).toList()),
              icon: const Icon(Icons.check),
              label: Text('Ajouter (${_selected.length})',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            ))
          : FloatingActionButton.extended(
              backgroundColor: kEduOrange, foregroundColor: Colors.white,
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Exercice', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kEduOrange))
          : _exercices.isEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.fitness_center_outlined, size: 56, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('Bibliothèque vide', style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.grey.shade400)),
                    const SizedBox(height: 6),
                    Text('Créez vos exercices une fois, réutilisez-les pour chaque famille.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400)),
                  ]),
                ))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                  itemCount: _exercices.length,
                  itemBuilder: (_, i) {
                    final e = _exercices[i];
                    final id = e['id'].toString();
                    final media = _mediaOf(e);
                    final cat = e['categorie']?.toString();
                    final picked = _selected.contains(id);
                    return GestureDetector(
                      onTap: widget.pickMode
                          ? () => setState(() => picked ? _selected.remove(id) : _selected.add(id))
                          : () => _edit(e),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: picked ? kEduOrange : Colors.transparent, width: 2),
                        ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (media.isNotEmpty)
                            Container(
                              width: 52, height: 52, margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                              clipBehavior: Clip.antiAlias,
                              child: media.first['type'] == 'video'
                                  ? const Icon(Icons.play_circle_outline, color: Colors.grey)
                                  : CachedNetworkImage(imageUrl: media.first['url']?.toString() ?? '', fit: BoxFit.cover),
                            ),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(e['titre']?.toString() ?? '',
                                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                            if (cat != null && kEduCategories[cat] != null)
                              Text(kEduCategories[cat]!,
                                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                            if ((e['description']?.toString() ?? '').isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(e['description'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          ])),
                          if (widget.pickMode)
                            Icon(picked ? Icons.check_circle : Icons.circle_outlined,
                                color: picked ? kEduOrange : Colors.grey.shade300)
                          else
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                              onPressed: () => _delete(e),
                            ),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}
