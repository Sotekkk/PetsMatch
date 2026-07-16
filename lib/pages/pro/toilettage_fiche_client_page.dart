import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/storage_helper.dart' as storage;

/// Fiche client (toiletteur) — préférences, historique des RDV passés pour
/// cet animal, photos avant/après. Une fiche par couple animal×pro,
/// accessible depuis pro_agenda.dart (callback onFiche).
class ToilettageFicheClientPage extends StatefulWidget {
  final String animalId;
  final String animalNom;
  final String rdvId;
  const ToilettageFicheClientPage({super.key, required this.animalId, required this.animalNom, required this.rdvId});

  @override
  State<ToilettageFicheClientPage> createState() => _ToilettageFicheClientPageState();
}

class _ToilettageFicheClientPageState extends State<ToilettageFicheClientPage> {
  static const _orange = Color(0xFFFFB74D);
  static const _bg = Color(0xFFF8F8F6);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  bool _uploading = false;
  String? _ficheId;
  final _shampooingCtrl = TextEditingController();
  final _allergiesCtrl = TextEditingController();
  final _coupeCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  List<Map<String, dynamic>> _historique = [];
  List<Map<String, dynamic>> _photosAvant = [];
  List<Map<String, dynamic>> _photosApres = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_shampooingCtrl, _allergiesCtrl, _coupeCtrl, _notesCtrl]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final pid = User_Info.activeProfileId;
    if (uid == null || pid.isEmpty) { setState(() => _loading = false); return; }
    try {
      var fiche = await _supa.from('fiches_toilettage').select()
          .eq('pro_profile_id', pid).eq('animal_id', widget.animalId).maybeSingle();
      if (fiche == null) {
        final rdv = await _supa.from('rdv').select('client_uid, client_profile_id').eq('id', widget.rdvId).maybeSingle();
        fiche = await _supa.from('fiches_toilettage').insert({
          'pro_uid': uid,
          'pro_profile_id': pid,
          'animal_id': widget.animalId,
          if (rdv?['client_uid'] != null) 'client_uid': rdv!['client_uid'],
          if (rdv?['client_profile_id'] != null) 'client_profile_id': rdv!['client_profile_id'],
        }).select().single();
      }
      _ficheId = fiche['id'] as String;
      _shampooingCtrl.text = fiche['shampooing_prefere']?.toString() ?? '';
      _allergiesCtrl.text = fiche['allergies']?.toString() ?? '';
      _coupeCtrl.text = fiche['coupe_habituelle']?.toString() ?? '';
      _notesCtrl.text = fiche['notes']?.toString() ?? '';

      final results = await Future.wait([
        _supa.from('rdv').select('date_heure, motif, statut')
            .eq('pro_uid', uid).eq('pro_profile_id', pid).eq('animal_id', widget.animalId)
            .eq('statut', 'termine').order('date_heure', ascending: false).limit(20),
        _supa.from('fiches_toilettage_photos').select().eq('fiche_id', _ficheId!).eq('type', 'avant').order('created_at', ascending: false),
        _supa.from('fiches_toilettage_photos').select().eq('fiche_id', _ficheId!).eq('type', 'apres').order('created_at', ascending: false),
      ]);

      if (mounted) setState(() {
        _historique = List<Map<String, dynamic>>.from(results[0] as List);
        _photosAvant = List<Map<String, dynamic>>.from(results[1] as List);
        _photosApres = List<Map<String, dynamic>>.from(results[2] as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePreferences() async {
    if (_ficheId == null) return;
    await _supa.from('fiches_toilettage').update({
      'shampooing_prefere': _shampooingCtrl.text.trim().isEmpty ? null : _shampooingCtrl.text.trim(),
      'allergies': _allergiesCtrl.text.trim().isEmpty ? null : _allergiesCtrl.text.trim(),
      'coupe_habituelle': _coupeCtrl.text.trim().isEmpty ? null : _coupeCtrl.text.trim(),
      'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    }).eq('id', _ficheId!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Préférences enregistrées.', style: TextStyle(fontFamily: 'Galey')),
        backgroundColor: Color(0xFF6E9E57)));
    }
  }

  Future<void> _uploadPhoto(String type) async {
    if (_ficheId == null) return;
    final file = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final path = 'fiches_toilettage/${_ficheId}_${type}_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final url = await storage.uploadPhoto(File(file.path), path);
      await _supa.from('fiches_toilettage_photos').insert({
        'fiche_id': _ficheId, 'rdv_id': widget.rdvId, 'type': type, 'url': url,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _photoRow(String title, String type, List<Map<String, dynamic>> photos) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Text(title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
        const Spacer(),
        TextButton.icon(
          onPressed: _uploading ? null : () => _uploadPhoto(type),
          icon: const Icon(Icons.camera_alt_outlined, size: 16),
          label: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
        ),
      ]),
      SizedBox(
        height: 90,
        child: photos.isEmpty
            ? Text('Aucune photo.', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400))
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(photos[i]['url'] as String, width: 90, height: 90, fit: BoxFit.cover),
                ),
              ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        title: Text('Fiche — ${widget.animalNom}', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _orange))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Préférences', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 10),
                    TextField(controller: _shampooingCtrl, style: const TextStyle(fontFamily: 'Galey'),
                        decoration: const InputDecoration(labelText: 'Shampooing préféré', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 10),
                    TextField(controller: _allergiesCtrl, style: const TextStyle(fontFamily: 'Galey'),
                        decoration: const InputDecoration(labelText: 'Allergies', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 10),
                    TextField(controller: _coupeCtrl, style: const TextStyle(fontFamily: 'Galey'),
                        decoration: const InputDecoration(labelText: 'Coupe habituelle', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 10),
                    TextField(controller: _notesCtrl, maxLines: 2, style: const TextStyle(fontFamily: 'Galey'),
                        decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: ElevatedButton(
                      onPressed: _savePreferences,
                      style: ElevatedButton.styleFrom(backgroundColor: _orange, foregroundColor: Colors.white),
                      child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                    )),
                  ]),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _photoRow('Avant', 'avant', _photosAvant),
                    const SizedBox(height: 12),
                    _photoRow('Après', 'apres', _photosApres),
                  ]),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Historique', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 8),
                    if (_historique.isEmpty)
                      Text('Aucun RDV terminé pour l\'instant.', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400))
                    else
                      ..._historique.map((h) {
                        final dh = DateTime.tryParse(h['date_heure']?.toString() ?? '');
                        final dateStr = dh != null ? DateFormat('d MMM yyyy', 'fr_FR').format(dh) : '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            Icon(Icons.check_circle_outline, size: 14, color: Colors.grey.shade400),
                            const SizedBox(width: 6),
                            Text(dateStr, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(h['motif']?.toString() ?? '', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600))),
                          ]),
                        );
                      }),
                  ]),
                ),
              ],
            ),
    );
  }
}
