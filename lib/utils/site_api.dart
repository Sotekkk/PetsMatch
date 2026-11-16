import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/main.dart' show User_Info;

/// En-têtes pour appeler une route /api du site (kSiteBaseUrl) : JSON + jeton
/// d'ID Firebase de l'utilisateur connecté. Les routes serveur en déduisent
/// l'identité de l'appelant (website/src/lib/server-auth.ts) — sans jeton,
/// les routes protégées (e-mails, certificats…) répondent 401.
Future<Map<String, String>> siteApiHeaders() async {
  final headers = {'Content-Type': 'application/json'};
  try {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token != null) headers['Authorization'] = 'Bearer $token';
  } catch (_) {}
  // Profil actif (indicatif) : ex. galerie d'un photographe ouverte depuis
  // son profil client (website/src/lib/galeries-server.ts roleLecture).
  if (User_Info.activeProfileId.isNotEmpty) headers['x-pm-profil'] = User_Info.activeProfileId;
  return headers;
}
