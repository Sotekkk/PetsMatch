import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/utils/storage_helper.dart' as storage;

/// Gestion de la bibliothèque musicale « maison » des stories (table
/// `story_music_tracks`) — SEULE source de musique disponible côté
/// utilisateur (aucun import libre, cf. story_music_picker.dart). Chaque
/// morceau doit être vérifié ici avant mise en ligne : licence CC0/libre
/// vérifiée = zéro contrainte, licence CC-BY = attribution obligatoire
/// (affichée automatiquement au visionnage, cf. StoryMusicTrack.displayAttribution).
///
/// Sources recommandées : Pixabay Music (pixabay.com/music — licence
/// "Content License", gratuite, AUCUNE attribution requise, la plus simple)
/// ou Incompetech/Kevin MacLeod (incompetech.com — CC-BY, attribution
/// obligatoire, à renseigner ici).
class StoryMusicAdminTab extends StatefulWidget {
  const StoryMusicAdminTab({super.key});

  @override
  State<StoryMusicAdminTab> createState() => _StoryMusicAdminTabState();
}

class _StoryMusicAdminTabState extends State<StoryMusicAdminTab> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;

  List<Map<String, dynamic>> _tracks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _supa.from('story_music_tracks').select().order('created_at', ascending: false);
      setState(() { _tracks = List<Map<String, dynamic>>.from(rows as List); _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleActif(Map<String, dynamic> t) async {
    final nouveau = !(t['actif'] as bool? ?? true);
    await _supa.from('story_music_tracks').update({'actif': nouveau}).eq('id', t['id']);
    await _load();
  }

  Future<void> _delete(Map<String, dynamic> t) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Supprimer ce morceau ?', style: TextStyle(fontFamily: 'Galey')),
      content: Text(t['titre']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    await _supa.from('story_music_tracks').delete().eq('id', t['id']);
    await _load();
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MusicFormSheet(existing: existing),
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
        label: const Text('Ajouter un morceau', style: TextStyle(fontFamily: 'Galey', color: Colors.white)),
        onPressed: () => _openForm(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _tracks.isEmpty
              ? const Center(child: Text('Aucun morceau dans la bibliothèque', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _teal,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _tracks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _TrackTile(
                      track: _tracks[i],
                      onEdit: () => _openForm(existing: _tracks[i]),
                      onToggle: () => _toggleActif(_tracks[i]),
                      onDelete: () => _delete(_tracks[i]),
                    ),
                  ),
                ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  final Map<String, dynamic> track;
  final VoidCallback onEdit, onToggle, onDelete;
  const _TrackTile({required this.track, required this.onEdit, required this.onToggle, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final actif = track['actif'] as bool? ?? true;
    final licence = track['licence']?.toString() ?? 'CC0';
    final attribution = track['attribution']?.toString();
    final licenceColor = switch (licence) {
      'CC-BY' => Colors.orange,
      'libre_verifie' => Colors.blue,
      _ => Colors.green,
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: _teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.music_note, color: _teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(track['titre']?.toString() ?? '',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                if (track['artiste'] != null)
                  Text(track['artiste'].toString(), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              ]),
            ),
            Switch(value: actif, onChanged: (_) => onToggle(), activeThumbColor: _teal),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: licenceColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(licence, style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: licenceColor)),
            ),
            if (licence == 'CC-BY') ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  attribution?.isNotEmpty == true ? '✓ $attribution' : '⚠️ Attribution manquante !',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                      color: attribution?.isNotEmpty == true ? Colors.grey.shade600 : Colors.red),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ]),
          const SizedBox(height: 6),
          Row(children: [
            TextButton(onPressed: onEdit, child: const Text('Modifier', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
            TextButton(onPressed: onDelete, child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.red))),
          ]),
        ]),
      ),
    );
  }
}

const _teal = Color(0xFF0C5C6C);

class _MusicFormSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _MusicFormSheet({this.existing});

  @override
  State<_MusicFormSheet> createState() => _MusicFormSheetState();
}

class _MusicFormSheetState extends State<_MusicFormSheet> {
  final _supa = Supabase.instance.client;

  late final _titreCtrl = TextEditingController(text: widget.existing?['titre']?.toString() ?? '');
  late final _artisteCtrl = TextEditingController(text: widget.existing?['artiste']?.toString() ?? '');
  late final _attributionCtrl = TextEditingController(text: widget.existing?['attribution']?.toString() ?? '');
  String _licence = 'CC0';
  File? _pickedAudio;
  String? _existingUrl;
  bool _saving = false;

  static const _licences = [
    ('CC0', 'CC0 / Content License', 'Aucune contrainte — Pixabay Music, domaine public'),
    ('libre_verifie', 'Libre vérifiée', 'Licence commerciale ou libre vérifiée à la main'),
    ('CC-BY', 'CC-BY', 'Attribution OBLIGATOIRE — ex. Incompetech/Kevin MacLeod'),
  ];

  @override
  void initState() {
    super.initState();
    _licence = widget.existing?['licence']?.toString() ?? 'CC0';
    _existingUrl = widget.existing?['url_audio']?.toString();
  }

  @override
  void dispose() {
    _titreCtrl.dispose(); _artisteCtrl.dispose(); _attributionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      setState(() => _pickedAudio = File(result.files.single.path!));
    }
  }

  Future<void> _submit() async {
    if (_titreCtrl.text.trim().isEmpty) return;
    if (_pickedAudio == null && (_existingUrl == null || _existingUrl!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajoutez un fichier audio')));
      return;
    }
    if (_licence == 'CC-BY' && _attributionCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Attribution obligatoire pour une licence CC-BY')));
      return;
    }
    setState(() => _saving = true);
    try {
      String audioUrl = _existingUrl ?? '';
      if (_pickedAudio != null) {
        final ext = _pickedAudio!.path.split('.').last.toLowerCase();
        final path = 'story_music/${DateTime.now().millisecondsSinceEpoch}.$ext';
        audioUrl = await storage.uploadRawFile(_pickedAudio!, path);
      }
      final data = {
        'titre': _titreCtrl.text.trim(),
        'artiste': _artisteCtrl.text.trim().isEmpty ? null : _artisteCtrl.text.trim(),
        'url_audio': audioUrl,
        'licence': _licence,
        'attribution': _licence == 'CC-BY' ? _attributionCtrl.text.trim() : null,
      };
      if (widget.existing != null) {
        await _supa.from('story_music_tracks').update(data).eq('id', widget.existing!['id']);
      } else {
        await _supa.from('story_music_tracks').insert(data);
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
      initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(widget.existing != null ? 'Modifier le morceau' : 'Ajouter un morceau',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 4),
            const Text('Vérifiez la licence AVANT d\'ajouter — voir les sources recommandées en commentaire du fichier.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 20),

            GestureDetector(
              onTap: _pickAudio,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade300)),
                child: Row(children: [
                  const Icon(Icons.audio_file_outlined, color: _teal),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _pickedAudio != null
                          ? _pickedAudio!.path.split('/').last
                          : (_existingUrl?.isNotEmpty == true ? 'Fichier existant (tap pour remplacer)' : 'Choisir un fichier audio (mp3, m4a…)'),
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            _field('Titre', _titreCtrl),
            const SizedBox(height: 12),
            _field('Artiste (optionnel)', _artisteCtrl),
            const SizedBox(height: 16),

            const Text('Licence', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 8),
            ..._licences.map((l) => RadioListTile<String>(
                  value: l.$1, groupValue: _licence,
                  onChanged: (v) => setState(() => _licence = v!),
                  activeColor: _teal,
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.$2, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(l.$3, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
                )),

            if (_licence == 'CC-BY') ...[
              const SizedBox(height: 8),
              _field('Attribution à afficher (obligatoire)', _attributionCtrl),
              const SizedBox(height: 4),
              Text('Ex : "Music by Kevin MacLeod (incompetech.com)"',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
            ],
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity, height: 50,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(backgroundColor: _teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(widget.existing != null ? 'Enregistrer' : 'Ajouter à la bibliothèque',
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
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
