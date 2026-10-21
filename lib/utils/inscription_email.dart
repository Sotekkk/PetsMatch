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
