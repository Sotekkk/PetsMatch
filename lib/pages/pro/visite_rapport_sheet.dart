import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/storage_helper.dart' as storage;

/// Bottom sheet « Rapport de visite » — transmettre des nouvelles + une photo
/// au propriétaire de l'animal (module garde / pet-sitting).
///
/// Réutilisable depuis le Registre des visites, Ma tournée et l'agenda.
/// `rdv` doit contenir au minimum : `animal_id`, `client_uid`. Les clés
/// `_animal_nom` / `client_profile_id` sont utilisées si présentes.
Future<void> showVisiteRapportSheet(BuildContext context, Map<String, dynamic> rdv) async {
  const teal = Color(0xFF0C5C6C);
  final noteCtrl = TextEditingController();
  File? photoFile;
  bool posting = false;
  final supa = Supabase.instance.client;

  final animalNom = (rdv['_animal_nom'] ?? rdv['animal_nom'] ?? rdv['_animal_name'] ?? '').toString();

  Future<void> envoyer() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final note = noteCtrl.text.trim();
    if (uid == null || (note.isEmpty && photoFile == null)) return;
    try {
      String? photoUrl;
      if (photoFile != null) {
        final path = 'visite_rapports/${uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        photoUrl = await storage.uploadPhoto(photoFile!, path, quality: 75);
      }
      await supa.from('pension_updates').insert({
        'animal_id': rdv['animal_id'],
        'pro_uid':   uid,
        'photo_url': photoUrl,
        'note':      note.isEmpty ? null : note,
      });
      final ownerUid = rdv['client_uid']?.toString();
      if (ownerUid != null && ownerUid.isNotEmpty) {
        final proNom = User_Info.nameElevage.isNotEmpty
            ? User_Info.nameElevage
            : '${User_Info.firstname} ${User_Info.lastname}'.trim();
        try {
          await supa.from('notifications').insert({
            'uid':   ownerUid,
            'type':  'visite_rapport',
            'title': 'Rapport de visite — $animalNom',
            'body':  '${proNom.isNotEmpty ? proNom : 'Votre pet sitter'} a envoyé un rapport pour $animalNom.',
            if (rdv['client_profile_id'] != null) 'profile_id': rdv['client_profile_id'],
            'data':  <String, dynamic>{
              'animalId': rdv['animal_id']?.toString() ?? '',
              'animalNom': animalNom,
            },
            'read':  false,
          });
        } catch (_) {}
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Rapport envoyé au propriétaire.', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Color(0xFF6E9E57),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          Text('Nouvelles pour ${animalNom.isEmpty ? "le propriétaire" : animalNom}',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          TextField(
            controller: noteCtrl,
            maxLines: 4,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Comment s\'est passée la visite/promenade…',
              hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () async {
                final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
                if (file == null) return;
                setSheetState(() => photoFile = File(file.path));
              },
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: Text(photoFile == null ? 'Ajouter une photo' : 'Photo ajoutée ✓',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: posting ? null : () async {
                setSheetState(() => posting = true);
                await envoyer();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: teal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: posting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Envoyer au propriétaire',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ]),
      ),
    ),
  );
}
