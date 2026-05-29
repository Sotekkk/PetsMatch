import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/bottom_nav.dart';
import 'package:PetsMatch/pages/eleveur/verification_page.dart';
import 'package:PetsMatch/pages/inscription_main.dart';
import 'package:PetsMatch/pages/password_oublier.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _showPass = false;
  bool _emailError = false;
  bool _passwordError = false;
  bool _loading = false;

  static const _green = Color(0xFF6E9E57);
  static const _teal = Color(0xFF0C5C6C);
  static const _bg = Color(0xFFF8F8F6);

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _emailError = _emailCtrl.text.trim().isEmpty;
      _passwordError = _passwordCtrl.text.isEmpty;
    });
    if (_emailError || _passwordError) return;

    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(cred.user!.uid)
          .get();
      User_Info.updateUserInfo(doc.data() as Map<String, dynamic>);
      // Sauvegarde du token FCM maintenant que l'user est authentifié
      saveFcmTokenToFirestore().catchError((_) {});

      if (!mounted) return;
      Widget dest = User_Info.isValidate || User_Info.isAdmin
          ? BottomNav()
          : VerificationRegistrationPage();
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => dest));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _emailError = true;
        _passwordError = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur [${e.code}]: ${e.message}',
              style: const TextStyle(fontFamily: 'Galey')),
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Connexion',
            style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Bon retour !',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                  color: Color(0xFF1F2A2E))),
          const SizedBox(height: 6),
          Text('Connectez-vous à votre compte PetsMatch.',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontSize: 13,
                  color: Colors.grey.shade500)),
          const SizedBox(height: 28),

          // ── Champs ────────────────────────────────────────────────────────────
          _card([
            _field(
              ctrl: _emailCtrl,
              label: 'Email',
              icon: Icons.email_outlined,
              keyboard: TextInputType.emailAddress,
              valid: !_emailError,
              error: 'Email requis',
            ),
            const SizedBox(height: 12),
            _passField(),
          ]),
          const SizedBox(height: 12),

          // ── Mot de passe oublié ───────────────────────────────────────────────
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => PasswordResetPage())),
              child: const Text('Mot de passe oublié ?',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 13,
                      color: _green,
                      decoration: TextDecoration.underline,
                      decorationColor: _green)),
            ),
          ),
          const SizedBox(height: 28),

          // ── Bouton connexion ──────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('SE CONNECTER',
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Colors.white)),
            ),
          ),
          const SizedBox(height: 28),

          // ── Lien inscription ──────────────────────────────────────────────────
          Center(
            child: GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const InscriptionChoicePage())),
              child: RichText(
                text: const TextSpan(
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 14,
                      color: Color(0xFF1F2A2E)),
                  children: [
                    TextSpan(text: "Pas encore de compte ? "),
                    TextSpan(
                      text: "S'inscrire",
                      style: TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                          decorationColor: _green),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    bool valid = true,
    String error = '',
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextFormField(
          controller: ctrl,
          keyboardType: keyboard,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(
                fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
            prefixIcon: Icon(icon, size: 18, color: const Color(0xFF6F767B)),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: valid ? const Color(0xFFE4E7E2) : Colors.red)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _green, width: 1.5)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            isDense: true,
          ),
        ),
        if (!valid)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(error,
                style: const TextStyle(
                    fontFamily: 'Galey', fontSize: 11, color: Colors.red)),
          ),
      ]);

  Widget _passField() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _passwordCtrl,
            obscureText: !_showPass,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              labelStyle: const TextStyle(
                  fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
              prefixIcon:
                  const Icon(Icons.lock_outline, size: 18, color: Color(0xFF6F767B)),
              suffixIcon: IconButton(
                icon: Icon(
                    _showPass
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: const Color(0xFF6F767B)),
                onPressed: () => setState(() => _showPass = !_showPass),
                padding: EdgeInsets.zero,
              ),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: !_passwordError
                          ? const Color(0xFFE4E7E2)
                          : Colors.red)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _green, width: 1.5)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              isDense: true,
            ),
          ),
          if (_passwordError)
            const Padding(
              padding: EdgeInsets.only(top: 4, left: 4),
              child: Text('Mot de passe requis',
                  style: TextStyle(
                      fontFamily: 'Galey', fontSize: 11, color: Colors.red)),
            ),
        ],
      );
}
