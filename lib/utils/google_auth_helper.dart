import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

// Client web (google-services.json, oauth_client de type 3) — même projet
// Firebase que le site, qui utilise déjà la connexion Google avec ce même
// identifiant. Requis en `serverClientId` pour obtenir un ID token que
// Firebase Auth peut vérifier.
const String _kGoogleServerClientId =
    '910914025100-aqrl52f3g1e0vib0ht89lhimscl6ad0c.apps.googleusercontent.com';

bool _googleInitialized = false;

Future<void> _ensureGoogleInitialized() async {
  if (_googleInitialized) return;
  await GoogleSignIn.instance.initialize(serverClientId: _kGoogleServerClientId);
  _googleInitialized = true;
}

/// Lance le flux de connexion Google et connecte l'utilisateur à Firebase
/// Auth. Retourne `null` si l'utilisateur a annulé la sélection de compte —
/// toute autre erreur est propagée pour être affichée à l'appelant.
Future<UserCredential?> signInWithGoogle() async {
  await _ensureGoogleInitialized();
  try {
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) return null;
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return await FirebaseAuth.instance.signInWithCredential(credential);
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) return null;
    rethrow;
  }
}

/// Le compte Firebase actuellement connecté l'est-il via Google ? (email
/// déjà vérifié par Google, aucun mot de passe créé côté PetsMatch — sert à
/// sauter les étapes mot de passe / vérification email du parcours
/// d'inscription classique.)
bool get isCurrentUserGoogleAuth => FirebaseAuth.instance.currentUser?.providerData
    .any((p) => p.providerId == 'google.com') ?? false;
