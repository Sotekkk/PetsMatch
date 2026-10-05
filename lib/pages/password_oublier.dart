import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Mot de passe oublié — nouveau design (miroir site /mot-de-passe-oublie).
/// Un seul envoi à la fois puis 60 s d'attente : chaque nouvel envoi rend le
/// lien de l'e-mail précédent invalide (« lien expiré » si on ouvre l'ancien).
class PasswordResetPage extends StatefulWidget {
  final String? emailInitial;
  const PasswordResetPage({super.key, this.emailInitial});

  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _bg = Color(0xFFF8F8F6);

  late final _emailCtrl = TextEditingController(text: widget.emailInitial ?? '');
  bool _envoi = false;
  bool _envoye = false;
  String? _erreur;
  int _attente = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    final email = _emailCtrl.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _erreur = 'Adresse e-mail invalide.');
      return;
    }
    if (_envoi || _attente > 0) return;
    setState(() { _envoi = true; _erreur = null; });
    try {
      await FirebaseAuth.instance.setLanguageCode('fr');
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      setState(() { _envoye = true; _attente = 60; });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _attente--);
        if (_attente <= 0) t.cancel();
      });
    } on FirebaseAuthException catch (e) {
      setState(() => _erreur = switch (e.code) {
        'invalid-email' => 'Adresse e-mail invalide.',
        'too-many-requests' => 'Trop de demandes. Réessayez dans quelques minutes.',
        // user-not-found : même message que le succès côté écran serait
        // plus sûr, mais on reste explicite pour la bêta.
        'user-not-found' => 'Aucun compte PetsMatch avec cette adresse.',
        _ => 'Envoi impossible (${e.code}). Réessayez.',
      });
    } catch (_) {
      setState(() => _erreur = 'Envoi impossible. Vérifiez votre connexion.');
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Mot de passe oublié', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Réinitialiser votre mot de passe',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Color(0xFF1F2A2E))),
          const SizedBox(height: 6),
          Text('Saisissez l\'adresse e-mail de votre compte : vous recevrez un lien pour choisir un nouveau mot de passe.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              onSubmitted: (_) => _envoyer(),
              decoration: InputDecoration(
                labelText: 'Adresse e-mail',
                prefixIcon: const Icon(Icons.mail_outline, color: _teal),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          if (_erreur != null) ...[
            const SizedBox(height: 12),
            Text(_erreur!, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.redAccent)),
          ],
          if (_envoye) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _green.withValues(alpha: 0.35)),
              ),
              child: Text(
                '✅ E-mail envoyé à ${_emailCtrl.text.trim()}.\n\n'
                '• Ouvrez le lien du DERNIER e-mail reçu : chaque nouvel envoi rend les précédents invalides.\n'
                '• Pensez à regarder dans les spams / courriers indésirables.\n'
                '• Le lien est valable 1 heure.',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4, color: Color(0xFF3D6B2E)),
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_envoi || _attente > 0) ? null : _envoyer,
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _envoi
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(
                      _attente > 0 ? 'Renvoyer dans $_attente s' : (_envoye ? 'Renvoyer l\'e-mail' : 'Envoyer le lien'),
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}
