import 'package:firebase_auth/firebase_auth.dart';
// Inscription : adresse prise par une inscription ABANDONNÉE (compte jamais
// validé) → la Cloud Function libererEmailInscription la supprime pour que la
// nouvelle inscription passe. Un compte validé n'est jamais touché.
// Miroir site : website/src/lib/inscription-email.ts.
import 'dart:convert';
import 'package:http/http.dart' as http;

const _kLibererUrl = 'https://europe-west1-petsmatch-eb96d.cloudfunctions.net/libererEmailInscription';

/// true si l'adresse est libre (ou vient d'être libérée).
Future<bool> libererEmailInscription(String email) async {
  try {
    final r = await http.post(Uri.parse(_kLibererUrl),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode({'email': email.trim()}))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return false;
    return (jsonDecode(r.body) as Map)['libere'] == true;
  } catch (_) {
    return false;
  }
}

const _kChangerUrl = 'https://europe-west1-petsmatch-eb96d.cloudfunctions.net/changerEmailInscription';

/// Adresse mal saisie (compte pas encore validé) : changée tout de suite sur le
/// même compte (informations gardées). Retourne un message d'erreur, ou null.
Future<String?> changerEmailInscription(String jeton, String email) async {
  try {
    final r = await http.post(Uri.parse(_kChangerUrl),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $jeton'},
        body: jsonEncode({'email': email.trim()})).timeout(const Duration(seconds: 20));
    if (r.statusCode == 200) {
      // Adresse changée = session fermée par Firebase : reconnexion automatique
      // (jeton fourni par la Cloud Function), sans rien demander à la personne.
      try {
        final jetonReco = (jsonDecode(r.body) as Map)['customToken'] as String?;
        if (jetonReco != null && jetonReco.isNotEmpty) {
          await FirebaseAuth.instance.signInWithCustomToken(jetonReco);
        }
      } catch (_) {}
      return null;
    }
    try { return (jsonDecode(r.body) as Map)['error']?.toString() ?? 'Changement impossible. Réessayez.'; } catch (_) {
      return 'Changement impossible. Réessayez.';
    }
  } catch (_) {
    return 'Pas de connexion. Réessayez.';
  }
}
