import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/storage_helper.dart';

/// Fichiers choisis pendant l'inscription : retenus en mémoire, puis
/// déposés une fois le compte créé (registerUser / registerElevage), dans
/// le dossier du compte. Le compte n'existe qu'à l'étape des CGU : tout dépôt
/// avant échouait (stockage refusé sans jeton — « new row violates row level
/// security policy », 403) — logo / bannière de « Informations société »,
/// KBIS / ACACED de l'étape documents.
class PhotosInscription {
  static File? photo;        // photo de profil
  static File? photoElevage; // logo élevage / association / société
  static File? banniere;     // bannière du profil pro
  static File? kbis;         // justificatif SIRET (KBIS…)
  static File? acaced;       // certificat ACACED ou équivalent

  /// Personne n'est encore connecté : les fichiers doivent être retenus.
  static bool get enAttenteDeCompte => FirebaseAuth.instance.currentUser == null;

  /// Dépose les fichiers retenus et renseigne User_Info (URL + entrées de
  /// User_Info.documentElevage). Sans effet si rien n'est retenu ou si
  /// personne n'est connecté. Ne lève jamais d'erreur.
  static Future<void> deposer() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    Future<void> essai(Future<void> Function() f) async {
      try { await f(); } catch (_) {
        // Non bloquant : l'inscription continue, le fichier pourra être
        // ajouté depuis le profil.
      }
    }
    await essai(() async {
      if (photo == null) return;
      User_Info.profilePictureUrl = await uploadPhoto(photo!, 'profiles/$uid/photo.jpg');
      photo = null;
    });
    await essai(() async {
      if (photoElevage == null) return;
      User_Info.profilePictureUrlElevage = await uploadPhoto(photoElevage!, 'profiles/$uid/photo_elevage.jpg');
      photoElevage = null;
    });
    await essai(() async {
      if (banniere == null) return;
      User_Info.bannerUrl = await uploadPhoto(banniere!, 'profiles/$uid/banner.jpg');
      banniere = null;
    });
    await essai(() async {
      if (kbis == null) return;
      final url = await uploadDocument(kbis!, _cheminDoc('Siret', uid, kbis!));
      User_Info.kbisUrl = url;
      _majDocument('Siret', url);
      kbis = null;
    });
    await essai(() async {
      if (acaced == null) return;
      final url = await uploadDocument(acaced!, _cheminDoc('Acaced', uid, acaced!));
      User_Info.acacedDocUrl = url;
      _majDocument('Acaced_ou_autre', url);
      acaced = null;
    });
  }

  /// Même schéma de chemin que l'étape documents (document_elevage.dart).
  static String _cheminDoc(String dossier, String uid, File f) =>
      'documentElevage/$dossier/$uid/${DateTime.now().millisecondsSinceEpoch}_${f.path.split('/').last}';

  static void _majDocument(String categorie, String url) {
    for (final d in User_Info.documentElevage) {
      if (d['category'] == categorie) d['url'] = url;
    }
  }
}
