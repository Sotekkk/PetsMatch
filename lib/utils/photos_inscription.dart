import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/storage_helper.dart';

/// Photos choisies pendant l'inscription : retenues en mémoire, puis
/// déposées une fois le compte créé (registerUser / registerElevage), dans
/// le dossier du compte — plus de dépôt anonyme avant la création du compte
/// (et, pour particulier / éleveur, le lien n'était même jamais enregistré).
class PhotosInscription {
  static File? photo;        // photo de profil
  static File? photoElevage; // logo élevage / association

  /// Dépose les photos retenues et renseigne User_Info. Sans effet si
  /// aucune photo ou si personne n'est connecté. Ne lève jamais d'erreur.
  static Future<void> deposer() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      if (photo != null) {
        User_Info.profilePictureUrl = await uploadPhoto(photo!, 'profiles/$uid/photo.jpg');
        photo = null;
      }
      if (photoElevage != null) {
        User_Info.profilePictureUrlElevage = await uploadPhoto(photoElevage!, 'profiles/$uid/photo_elevage.jpg');
        photoElevage = null;
      }
    } catch (_) {
      // Photo non bloquante : l'inscription continue, la photo pourra être
      // ajoutée depuis le profil.
    }
  }
}
