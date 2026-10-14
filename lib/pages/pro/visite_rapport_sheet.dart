import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/storage_helper.dart' as storage;
import 'package:PetsMatch/pages/pro/pension_journal_page.dart';

/// Point d'entrée « envoyer des nouvelles » depuis le registre / la tournée /
/// l'agenda. Une **promenade ou une visite courte** → feuille « rapport »
/// unique. Une **garde** (garde-journée ou durée ≥ 24 h) → **journal de garde**
/// multi-entrées (comme le journal de pension), que le pet-sitter alimente à la
/// fréquence qu'il veut.
Future<void> sendGardeNews(BuildContext context, Map<String, dynamic> rdv) async {
  final motif = (rdv['motif'] ?? rdv['_motif'] ?? '').toString().toLowerCase();
  final dureeMin = rdv['duree_minutes'] is int
      ? rdv['duree_minutes'] as int
      : int.tryParse(rdv['duree_minutes']?.toString() ?? '') ?? 0;
  final isGarde = motif.contains('garde') || motif.contains('journ') || dureeMin >= 24 * 60;
  final animalId = rdv['animal_id']?.toString();

  if (isGarde && animalId != null && animalId.isNotEmpty) {
    final animalNom = (rdv['_animal_nom'] ?? rdv['animal_nom'] ?? rdv['_animal_name'] ?? 'Animal').toString();
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => PensionJournalPage(
        animalId: animalId,
        animalNom: animalNom.isEmpty ? 'Animal' : animalNom,
        journalKind: 'garde',
        clientUid: rdv['client_uid']?.toString(),
        clientProfileId: rdv['client_profile_id']?.toString(),
      ),
    ));
    return;
  }
  await showVisiteRapportSheet(context, rdv);
}

/// Éléments cochables du compte rendu express, selon la prestation.
const _kItemsPromenade = <(String, String)>[
  ('ok', "Tout s'est bien passé"), ('besoins', 'Besoins effectués'),
  ('eau', 'Eau proposée'), ('jeux', 'Jeux / activité'),
];
const _kItemsVisite = <(String, String)>[
  ('ok', "Tout s'est bien passé"), ('repas', 'Repas donné'), ('eau', 'Eau renouvelée'),
  ('litiere', 'Litière / besoins'), ('consignes', 'Consignes effectuées'),
  ('medicament', 'Médicament donné selon les consignes'),
];

/// Message lisible généré à partir des éléments cochés (aucune rédaction
/// imposée au pet-sitter). Ex. « La promenade de Luna est terminée. Tout
/// s'est bien passé. Luna a fait ses besoins… Une photo est disponible. »
/// Miroir site : messageCompteRendu (lib/compte-rendu-garde.ts).
String messageCompteRendu({
  required bool promenade, required bool equide, required String animal, required Set<String> items,
  String comportement = '', String incident = '', String note = '', int nbPhotos = 0,
}) {
  final a = animal.isEmpty ? "l'animal" : animal;
  final sujet = animal.isEmpty ? "L'animal" : animal;
  String fin(String t) => t.trim().endsWith('.') ? t.trim() : '${t.trim()}.';
  final phrases = <String>[
    promenade
        ? (equide ? 'La sortie au paddock de $a est terminée.' : 'La promenade de $a est terminée.')
        : 'La visite pour $a est terminée.',
    if (items.contains('ok')) "Tout s'est bien passé.",
    if (items.contains('besoins')) '$sujet a fait ses besoins.',
    if (items.contains('repas')) 'Le repas a été donné.',
    if (items.contains('eau')) promenade ? "De l'eau a été proposée." : "L'eau a été renouvelée.",
    if (items.contains('litiere')) 'La litière et les besoins ont été gérés.',
    if (items.contains('jeux')) "$sujet a profité de jeux et d'activité.",
    if (items.contains('consignes')) 'Vos consignes ont été suivies.',
    if (items.contains('medicament')) 'Le traitement a été donné selon vos consignes.',
    if (comportement.trim().isNotEmpty) 'Comportement : ${fin(comportement)}',
    if (incident.trim().isNotEmpty) 'Incident signalé : ${fin(incident)}',
    if (note.trim().isNotEmpty) note.trim(),
    if (nbPhotos == 1) 'Une photo est disponible.' else if (nbPhotos > 1) '$nbPhotos photos sont disponibles.',
  ];
  return phrases.join(' ');
}

/// Bottom sheet « Compte rendu express » d'une promenade / visite (module
/// garde) : éléments à cocher selon la prestation, message généré, aperçu,
/// photos et signalement d'incident facultatifs, envoi après validation.
/// Enregistré dans pension_updates (historique, rattaché au RDV si la
/// migration migration_garde_compte_rendu_express.sql est passée) + la
/// notification existante au propriétaire. Aucun PDF.
///
/// Réutilisable depuis le tableau de bord, le Registre, Ma tournée et
/// l'agenda. `rdv` doit contenir au minimum `animal_id`, `client_uid`.
/// Renvoie true si le compte rendu a été envoyé.
Future<bool> showVisiteRapportSheet(BuildContext context, Map<String, dynamic> rdv) async {
  const teal = Color(0xFF0C5C6C);
  const rouge = Color(0xFFB3261E);
  final noteCtrl = TextEditingController();
  final comportementCtrl = TextEditingController();
  final incidentCtrl = TextEditingController();
  final photos = <File>[];
  final items = <String>{};
  bool avecComportement = false;
  bool avecIncident = false;
  bool posting = false;
  bool envoye = false;
  final supa = Supabase.instance.client;

  final animalNom = (rdv['_animal_nom'] ?? rdv['animal_nom'] ?? rdv['_animal_name'] ?? '').toString();
  final motif = (rdv['motif'] ?? rdv['_motif'] ?? '').toString().toLowerCase();
  final isPromenade = motif.contains('promenade') || motif.contains('balade');

  // Équidé : « promenade » → « sortie au paddock » dans les libellés.
  var isEquide = false;
  final animalId = rdv['animal_id']?.toString();
  if (isPromenade && animalId != null && animalId.isNotEmpty) {
    try {
      final row = await supa.from('animaux').select('espece').eq('id', animalId).maybeSingle();
      final e = (row?['espece'] as String?)?.toLowerCase().trim() ?? '';
      isEquide = e == 'cheval' || e == 'poney' || e == 'ane' || e == 'âne';
    } catch (_) {}
  }

  final kindLabel = isPromenade
      ? (isEquide ? 'Compte rendu de sortie au paddock' : 'Compte rendu de promenade')
      : 'Compte rendu de visite';
  final choix = isPromenade ? _kItemsPromenade : _kItemsVisite;

  String message() => messageCompteRendu(
        promenade: isPromenade, equide: isEquide, animal: animalNom, items: items,
        comportement: avecComportement ? comportementCtrl.text : '',
        incident: avecIncident ? incidentCtrl.text : '',
        note: noteCtrl.text, nbPhotos: photos.length,
      );

  Future<void> envoyer() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final texte = message();
    final incident = avecIncident && incidentCtrl.text.trim().isNotEmpty;
    try {
      final urls = <String>[];
      for (final (i, f) in photos.indexed) {
        final path = 'visite_rapports/${uid}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        urls.add(await storage.uploadPhotoPrive(f, path, quality: 75));
      }
      // Une entrée = le message (+ 1re photo) ; photos suivantes : entrées photo.
      final lignes = <Map<String, dynamic>>[
        {'note': texte, 'photo_url': urls.isNotEmpty ? urls.first : null},
        for (final u in urls.skip(1)) {'note': null, 'photo_url': u},
      ];
      for (final (i, l) in lignes.indexed) {
        final base = <String, dynamic>{'animal_id': rdv['animal_id'], 'pro_uid': uid, ...l};
        try {
          await supa.from('pension_updates').insert({
            ...base,
            if (rdv['id'] != null) 'rdv_id': rdv['id'],
            if (i == 0) 'incident': incident,
          });
        } on PostgrestException {
          // Migration migration_garde_compte_rendu_express.sql pas encore passée.
          await supa.from('pension_updates').insert(base);
        }
      }
      final ownerUid = rdv['client_uid']?.toString();
      if (ownerUid != null && ownerUid.isNotEmpty) {
        final proNom = User_Info.nameElevage.isNotEmpty
            ? User_Info.nameElevage
            : '${User_Info.firstname} ${User_Info.lastname}'.trim();
        // Profil destinataire : celui du RDV, sinon le profil PARTICULIER du
        // propriétaire (is_main peut être un profil éleveur/pro → la notif
        // n'apparaîtrait pas dans sa liste « particulier »).
        var destPid = rdv['client_profile_id']?.toString();
        if (destPid == null || destPid.isEmpty) {
          try {
            final p = await supa.from('user_profiles_complet')
                .select('id').eq('uid', ownerUid).eq('profile_type', 'particulier')
                .order('is_main', ascending: false).limit(1).maybeSingle();
            destPid = p?['id'] as String?;
          } catch (_) {}
        }
        try {
          // Jamais de code d'accès ni d'info sensible : seulement le message.
          final extrait = texte.length > 160 ? '${texte.substring(0, 157)}…' : texte;
          await supa.from('notifications').insert({
            'uid':   ownerUid,
            'type':  'visite_rapport',
            'title': '${incident ? 'Incident — ' : ''}$kindLabel${animalNom.isEmpty ? '' : ' — $animalNom'}',
            'body':  '${proNom.isNotEmpty ? proNom : 'Votre pet sitter'} : $extrait',
            if (destPid != null && destPid.isNotEmpty) 'profile_id': destPid,
            'data':  <String, dynamic>{
              'animalId': rdv['animal_id']?.toString() ?? '',
              'animalNom': animalNom,
              if (rdv['id'] != null) 'rdvId': rdv['id'].toString(),
              if (incident) 'incident': true,
            },
            'read':  false,
          });
        } catch (_) {}
      }
      envoye = true;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Compte rendu envoyé au propriétaire.', style: TextStyle(fontFamily: 'Galey')),
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

  InputDecoration deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey, fontSize: 13),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.all(10),
      );

  Widget puce(String label, bool actif, ValueChanged<bool> onSel, {Color couleur = teal, Color fond = const Color(0xFFF1F4F3)}) =>
      FilterChip(
        label: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
            color: actif ? Colors.white : (couleur == teal ? const Color(0xFF1F2A2E) : couleur))),
        selected: actif, showCheckmark: false, selectedColor: couleur,
        backgroundColor: fond, side: BorderSide.none, onSelected: onSel,
      );

  if (!context.mounted) return false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            Text('$kindLabel${animalNom.isEmpty ? "" : " — $animalNom"}',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in choix)
                puce(c.$2, items.contains(c.$1), (v) => setSheetState(() => v ? items.add(c.$1) : items.remove(c.$1))),
              puce('Comportement particulier', avecComportement, (v) => setSheetState(() => avecComportement = v)),
              puce('Incident', avecIncident, (v) => setSheetState(() => avecIncident = v),
                  couleur: rouge, fond: const Color(0xFFFDECEA)),
            ]),
            if (avecComportement) ...[
              const SizedBox(height: 10),
              TextField(controller: comportementCtrl, onChanged: (_) => setSheetState(() {}),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14), decoration: deco('Ex : un peu craintif avec les vélos')),
            ],
            if (avecIncident) ...[
              const SizedBox(height: 10),
              TextField(controller: incidentCtrl, onChanged: (_) => setSheetState(() {}), maxLines: 2,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14), decoration: deco("Que s'est-il passé ?")),
            ],
            const SizedBox(height: 10),
            TextField(controller: noteCtrl, onChanged: (_) => setSheetState(() {}), maxLines: 2,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14), decoration: deco('Note libre (facultatif)')),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final f in photos)
                Stack(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(f, width: 56, height: 56, fit: BoxFit.cover)),
                  Positioned(top: 1, right: 1, child: InkWell(
                    onTap: () => setSheetState(() => photos.remove(f)),
                    child: const CircleAvatar(radius: 9, backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 12, color: Colors.white)),
                  )),
                ]),
              OutlinedButton.icon(
                onPressed: () async {
                  final f = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
                  if (f != null) setSheetState(() => photos.add(File(f.path)));
                },
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Photo', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final fs = await ImagePicker().pickMultiImage(imageQuality: 85);
                  if (fs.isNotEmpty) setSheetState(() => photos.addAll(fs.map((x) => File(x.path))));
                },
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Galerie', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
              ),
            ]),
            const SizedBox(height: 14),
            // Aperçu du message tel que le propriétaire le recevra.
            Text('Aperçu', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: avecIncident ? const Color(0xFFFDECEA) : const Color(0xFFF1F5F4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(message(), style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, height: 1.4)),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: posting || (avecIncident && incidentCtrl.text.trim().isEmpty) ? null : () async {
                  setSheetState(() => posting = true);
                  await envoyer();
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: avecIncident ? rouge : teal, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: posting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Valider et envoyer au propriétaire',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
  return envoye;
}
