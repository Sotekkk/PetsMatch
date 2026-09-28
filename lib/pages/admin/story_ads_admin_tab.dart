import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/utils/storage_helper.dart' as storage;

/// Gestion des stories publicitaires (régie interne, cf.
/// lib/pages/particulier/stories/story_ad_service.dart) — table `story_ads`.
/// Les pubs actives sont injectées côté client toutes les N stories
/// cumulées vues dans StoryRing, avec les mêmes barres de progression/plein
/// écran qu'une story normale.
class StoryAdsAdminTab extends StatefulWidget {
  const StoryAdsAdminTab({super.key});

  @override
  State<StoryAdsAdminTab> createState() => _StoryAdsAdminTabState();
}

class _StoryAdsAdminTabState extends State<StoryAdsAdminTab> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;

  List<Map<String, dynamic>> _ads = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _supa.from('story_ads').select().order('created_at', ascending: false);
      setState(() { _ads = List<Map<String, dynamic>>.from(rows as List); _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleActif(Map<String, dynamic> ad) async {
    final nouveau = !(ad['actif'] as bool? ?? true);
    await _supa.from('story_ads').update({'actif': nouveau}).eq('id', ad['id']);
    await _load();
  }

  Future<void> _delete(Map<String, dynamic> ad) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Supprimer cette pub ?', style: TextStyle(fontFamily: 'Galey')),
      content: Text(ad['annonceur_nom']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    await _supa.from('story_ads').delete().eq('id', ad['id']);
    await _load();
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StoryAdFormSheet(existing: existing),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _teal,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nouvelle pub', style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
        onPressed: () => _openForm(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _ads.isEmpty
              ? const Center(child: Text('Aucune story publicitaire', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _teal,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _ads.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _AdTile(
                      ad: _ads[i],
                      onEdit: () => _openForm(existing: _ads[i]),
                      onToggle: () => _toggleActif(_ads[i]),
                      onDelete: () => _delete(_ads[i]),
                    ),
                  ),
                ),
    );
  }
}

class _AdTile extends StatelessWidget {
  final Map<String, dynamic> ad;
  final VoidCallback onEdit, onToggle, onDelete;
  const _AdTile({required this.ad, required this.onEdit, required this.onToggle, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final actif = ad['actif'] as bool? ?? true;
    final impressions = ad['impressions'] as int? ?? 0;
    final clics = ad['clics'] as int? ?? 0;
    final dateFin = ad['date_fin'] != null ? DateTime.tryParse(ad['date_fin'].toString()) : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 64, height: 64,
              child: (ad['media_url'] as String?)?.isNotEmpty == true
                  ? CachedNetworkImage(imageUrl: ad['media_url'], fit: BoxFit.cover)
                  : Container(color: Colors.grey.shade200, child: const Icon(Icons.image_outlined, color: Colors.grey)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(ad['annonceur_nom']?.toString() ?? '',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15))),
                Switch(value: actif, onChanged: (_) => onToggle(), activeThumbColor: const Color(0xFF0C5C6C)),
              ]),
              Text(ad['media_type'] == 'video' ? 'Vidéo' : 'Photo',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text('👁 $impressions vues  ·  👆 $clics clics',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              if (dateFin != null)
                Text('Fin : ${DateFormat('dd/MM/yyyy').format(dateFin)}',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
              const SizedBox(height: 6),
              Row(children: [
                TextButton(onPressed: onEdit, child: const Text('Modifier', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
                TextButton(onPressed: onDelete, child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.red))),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _StoryAdFormSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _StoryAdFormSheet({this.existing});

  @override
  State<_StoryAdFormSheet> createState() => _StoryAdFormSheetState();
}

class _StoryAdFormSheetState extends State<_StoryAdFormSheet> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;

  late final _nomCtrl = TextEditingController(text: widget.existing?['annonceur_nom']?.toString() ?? '');
  late final _ctaCtrl = TextEditingController(text: widget.existing?['cta_label']?.toString() ?? 'En savoir plus');
  late final _lienCtrl = TextEditingController(text: widget.existing?['lien_url']?.toString() ?? '');
  late final _poidsCtrl = TextEditingController(text: (widget.existing?['poids'] ?? 1).toString());
  String _mediaType = 'photo';
  File? _pickedFile;
  String? _existingMediaUrl;
  DateTime? _dateFin;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mediaType = widget.existing?['media_type']?.toString() ?? 'photo';
    _existingMediaUrl = widget.existing?['media_url']?.toString();
    final df = widget.existing?['date_fin'];
    if (df != null) _dateFin = DateTime.tryParse(df.toString());
  }

  @override
  void dispose() {
    _nomCtrl.dispose(); _ctaCtrl.dispose(); _lienCtrl.dispose(); _poidsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final picker = ImagePicker();
    final file = _mediaType == 'video'
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file != null) setState(() => _pickedFile = File(file.path));
  }

  Future<void> _pickDateFin() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dateFin ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _dateFin = d);
  }

  Future<void> _submit() async {
    if (_nomCtrl.text.trim().isEmpty) return;
    if (_pickedFile == null && (_existingMediaUrl == null || _existingMediaUrl!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajoutez une image ou vidéo')));
      return;
    }
    setState(() => _saving = true);
    try {
      String mediaUrl = _existingMediaUrl ?? '';
      if (_pickedFile != null) {
        if (_mediaType == 'video') {
          final ext = _pickedFile!.path.split('.').last.toLowerCase();
          final path = 'ads/${DateTime.now().millisecondsSinceEpoch}.$ext';
          mediaUrl = await storage.uploadRawFile(_pickedFile!, path);
        } else {
          final path = 'ads/${DateTime.now().millisecondsSinceEpoch}.jpg';
          mediaUrl = await storage.uploadPhoto(_pickedFile!, path);
        }
      }
      final data = {
        'annonceur_nom': _nomCtrl.text.trim(),
        'media_url': mediaUrl,
        'media_type': _mediaType,
        'cta_label': _ctaCtrl.text.trim().isEmpty ? 'En savoir plus' : _ctaCtrl.text.trim(),
        'lien_url': _lienCtrl.text.trim().isEmpty ? null : _lienCtrl.text.trim(),
        'poids': int.tryParse(_poidsCtrl.text.trim()) ?? 1,
        'date_fin': _dateFin?.toIso8601String(),
      };
      if (widget.existing != null) {
        await _supa.from('story_ads').update(data).eq('id', widget.existing!['id']);
      } else {
        await _supa.from('story_ads').insert(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9, maxChildSize: 0.95, minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(widget.existing != null ? 'Modifier la pub' : 'Nouvelle story pub',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 20),

            GestureDetector(
              onTap: _pickMedia,
              child: Container(
                height: 160,
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade300)),
                clipBehavior: Clip.antiAlias,
                child: _pickedFile != null
                    ? (_mediaType == 'video'
                        ? const Center(child: Icon(Icons.videocam, size: 40, color: Colors.grey))
                        : Image.file(_pickedFile!, fit: BoxFit.cover, width: double.infinity))
                    : (_existingMediaUrl?.isNotEmpty == true
                        ? CachedNetworkImage(imageUrl: _existingMediaUrl!, fit: BoxFit.cover, width: double.infinity)
                        : const Center(child: Icon(Icons.add_photo_alternate_outlined, size: 40, color: Colors.grey))),
              ),
            ),
            const SizedBox(height: 12),

            Row(children: [
              Expanded(child: _typeChip('photo', 'Photo')),
              const SizedBox(width: 8),
              Expanded(child: _typeChip('video', 'Vidéo')),
            ]),
            const SizedBox(height: 16),

            _field('Nom de l\'annonceur', _nomCtrl),
            const SizedBox(height: 12),
            _field('Texte du bouton (CTA)', _ctaCtrl),
            const SizedBox(height: 12),
            _field('Lien (https://...)', _lienCtrl, keyboardType: TextInputType.url),
            const SizedBox(height: 12),
            _field('Poids (priorité si plusieurs pubs)', _poidsCtrl, keyboardType: TextInputType.number),
            const SizedBox(height: 12),

            GestureDetector(
              onTap: _pickDateFin,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.event_outlined, size: 18, color: Colors.grey),
                  const SizedBox(width: 10),
                  Text(_dateFin != null ? 'Fin : ${DateFormat('dd/MM/yyyy').format(_dateFin!)}' : 'Date de fin (optionnel)',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _dateFin != null ? Colors.black87 : Colors.grey)),
                  const Spacer(),
                  if (_dateFin != null)
                    GestureDetector(onTap: () => setState(() => _dateFin = null), child: const Icon(Icons.close, size: 16, color: Colors.grey)),
                ]),
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity, height: 50,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(backgroundColor: _teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(widget.existing != null ? 'Enregistrer' : 'Créer la pub', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(String value, String label) {
    final active = _mediaType == value;
    return GestureDetector(
      onTap: () => setState(() => _mediaType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? _teal.withValues(alpha: 0.12) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? _teal : Colors.transparent),
        ),
        child: Text(label, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: active ? _teal : Colors.grey.shade600)),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        filled: true, fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
