import 'package:firebase_auth/firebase_auth.dart';

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
  return headers;
}
