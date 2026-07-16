import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/storage_helper.dart' as storage;

const _kAlbumBaseUrl = 'https://www.petsmatchapp.com/album/';

/// Galerie de livraison (photographe animalier) — un album par prestation
/// (rattaché au rdv), upload multi-photos, favoris, partage public par
/// token (calqué sur partage_animal_sheet.dart).
class PhotographeAlbumPage extends StatefulWidget {
  final String rdvId;
  final String clientName;
  const PhotographeAlbumPage({super.key, required this.rdvId, required this.clientName});

  @override
  State<PhotographeAlbumPage> createState() => _PhotographeAlbumPageState();
}

class _PhotographeAlbumPageState extends State<PhotographeAlbumPage> {
  static const _teal = Color(0xFF90A4AE);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  bool _uploading = false;
  String? _albumId;
  List<Map<String, dynamic>> _photos = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      var album = await _supa.from('albums_photo').select('id')
          .eq('rdv_id', widget.rdvId).maybeSingle();
      if (album == null) {
        final rdv = await _supa.from('rdv').select('client_uid, client_profile_id')
            .eq('id', widget.rdvId).maybeSingle();
        album = await _supa.from('albums_photo').insert({
          'pro_uid': uid,
          if (User_Info.activeProfileId.isNotEmpty) 'pro_profile_id': User_Info.activeProfileId,
          'rdv_id': widget.rdvId,
          if (rdv?['client_uid'] != null) 'client_uid': rdv!['client_uid'],
          if (rdv?['client_profile_id'] != null) 'client_profile_id': rdv!['client_profile_id'],
          'titre': 'Séance photo — ${widget.clientName}',
        }).select('id').single();
      }
      _albumId = album['id'] as String;
      final photos = await _supa.from('album_photos').select()
          .eq('album_id', _albumId!).order('created_at', ascending: false);
      if (mounted) setState(() { _photos = List<Map<String, dynamic>>.from(photos as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _uploadPhotos() async {
    if (_albumId == null) return;
    final files = await ImagePicker().pickMultiImage(imageQuality: 90);
    if (files.isEmpty) return;
    setState(() => _uploading = true);
    try {
      for (final f in files) {
        final path = 'albums_photo/${_albumId}_${DateTime.now().microsecondsSinceEpoch}.jpg';
        final url = await storage.uploadPhoto(File(f.path), path, maxDim: 2000, quality: 90);
        await _supa.from('album_photos').insert({'album_id': _albumId, 'photo_url': url});
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _toggleFavori(Map<String, dynamic> photo) async {
    await _supa.from('album_photos').update({'favori': !(photo['favori'] as bool? ?? false)}).eq('id', photo['id']);
    await _load();
  }

  Future<void> _deletePhoto(String id) async {
    await _supa.from('album_photos').delete().eq('id', id);
    await _load();
  }

  Future<void> _openPartage() async {
    if (_albumId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _PartageAlbumSheet(albumId: _albumId!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text('Galerie — ${widget.clientName}', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.share_outlined), tooltip: 'Partager', onPressed: _openPartage),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _teal,
        onPressed: _uploading ? null : _uploadPhotos,
        icon: _uploading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.add_photo_alternate_outlined, color: Colors.white),
        label: Text(_uploading ? 'Envoi...' : 'Ajouter des photos', style: const TextStyle(fontFamily: 'Galey', color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _photos.isEmpty
              ? const Center(child: Text('Aucune photo livrée pour l\'instant.', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6),
                  itemCount: _photos.length,
                  itemBuilder: (_, i) {
                    final p = _photos[i];
                    final favori = p['favori'] as bool? ?? false;
                    return Stack(children: [
                      Positioned.fill(child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(p['photo_url'] as String, fit: BoxFit.cover),
                      )),
                      Positioned(
                        top: 4, right: 4,
                        child: GestureDetector(
                          onTap: () => _toggleFavori(p),
                          child: Icon(favori ? Icons.favorite : Icons.favorite_border,
                              color: favori ? Colors.redAccent : Colors.white, size: 20,
                              shadows: const [Shadow(color: Colors.black45, blurRadius: 4)]),
                        ),
                      ),
                      Positioned(
                        bottom: 4, right: 4,
                        child: GestureDetector(
                          onTap: () => _deletePhoto(p['id'].toString()),
                          child: const Icon(Icons.delete_outline, color: Colors.white, size: 18,
                              shadows: [Shadow(color: Colors.black45, blurRadius: 4)]),
                        ),
                      ),
                    ]);
                  },
                ),
    );
  }
}

class _PartageAlbumSheet extends StatefulWidget {
  final String albumId;
  const _PartageAlbumSheet({required this.albumId});

  @override
  State<_PartageAlbumSheet> createState() => _PartageAlbumSheetState();
}

class _PartageAlbumSheetState extends State<_PartageAlbumSheet> {
  final _supa = Supabase.instance.client;
  static const _durees = [('7 jours', 7), ('30 jours', 30), ('90 jours', 90)];
  int _dureeJours = 30;
  bool _creating = false;
  String? _token;

  Future<void> _createLien() async {
    setState(() => _creating = true);
    try {
      final expireAt = DateTime.now().add(Duration(days: _dureeJours)).toUtc();
      final data = await _supa.from('album_partage').insert({
        'album_id': widget.albumId,
        'expire_at': expireAt.toIso8601String(),
        'actif': true,
      }).select('token').single();
      setState(() { _token = data['token'] as String; _creating = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = _token != null ? '$_kAlbumBaseUrl$_token' : null;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Partager la galerie', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 6),
          const Text('Lien de téléchargement — le client peut voir et télécharger les photos sans compte.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, children: _durees.map((d) {
            final selected = _dureeJours == d.$2;
            return ChoiceChip(
              label: Text(d.$1, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: selected ? Colors.white : Colors.black87)),
              selected: selected,
              selectedColor: const Color(0xFF90A4AE),
              onSelected: (_) => setState(() => _dureeJours = d.$2),
            );
          }).toList()),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: _creating ? null : _createLien,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF90A4AE), padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: _creating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.add_link, color: Colors.white),
            label: Text(_creating ? 'Génération...' : 'Créer le lien', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
          )),
          if (link != null) ...[
            const SizedBox(height: 20),
            Center(child: QrImageView(data: link, size: 160, backgroundColor: Colors.white)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(10)),
              child: Text(link, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Galey', fontSize: 11)),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: link));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lien copié !', style: TextStyle(fontFamily: 'Galey'))));
                },
                icon: const Icon(Icons.copy_outlined, size: 14),
                label: const Text('Copier', style: TextStyle(fontFamily: 'Galey')),
              )),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton.icon(
                onPressed: () => Share.share(link),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0C5C6C), foregroundColor: Colors.white),
                icon: const Icon(Icons.ios_share_rounded, size: 14),
                label: const Text('Partager', style: TextStyle(fontFamily: 'Galey')),
              )),
            ]),
          ],
        ]),
      ),
    );
  }
}
