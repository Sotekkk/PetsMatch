import 'package:PetsMatch/main.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'dart:async';
import 'package:PetsMatch/utils/google_auth_helper.dart';
import 'package:flutter/material.dart';

/// Première étape de l'inscription : e-mail + mot de passe. Le compte est
/// créé ICI (et l'e-mail de vérification envoyé) : une adresse déjà utilisée
/// ou invalide se voit tout de suite, avant de remplir le reste. [suivante] =
/// l'étape d'informations du type de compte choisi.
class RegisterSecurity extends StatefulWidget {
  final Widget Function() suivante;
  const RegisterSecurity({super.key, required this.suivante});
  @override
  State<RegisterSecurity> createState() => _RegisterSecurityState();
}

class _RegisterSecurityState extends State<RegisterSecurity> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _verifCtrl    = TextEditingController();

  bool _showPass  = false;
  bool _showPass2 = false;

  bool _emailOk  = true;
  bool _passOk   = true;
  bool _verifOk  = true;
  bool _googleLoading = false;
  bool _creation = false;
  String? _erreur;

  static const _green = Color(0xFF6E9E57);
  static const _teal  = Color(0xFF0C5C6C);
  static const _bg    = Color(0xFFF8F8F6);

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _verifCtrl.dispose();
    super.dispose();
  }

  int _strength(String p) {
    int s = 0;
    if (p.length >= 8)                        s++;
    if (RegExp(r'[A-Z]').hasMatch(p))         s++;
    if (RegExp(r'[a-z]').hasMatch(p))         s++;
    if (RegExp(r'[0-9]').hasMatch(p))         s++;
    if (RegExp(r'[\W]').hasMatch(p))          s++;
    return s;
  }

  Future<void> _continue() async {
    if (_creation) return;
    final e = _emailCtrl.text.trim();
    final p = _passwordCtrl.text;
    final v = _verifCtrl.text;
    setState(() {
      _emailOk = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e);
      _passOk  = p.length >= 6;
      _verifOk = v == p && v.isNotEmpty;
      _erreur = null;
    });
    if (!_emailOk || !_passOk || !_verifOk) return;

    User_Info.email    = e;
    User_Info.password = p;
    // Avant la création : l'écran racine (qui réagit à la connexion) reste neutre.
    User_Info.inscriptionEnCours = true;
    setState(() => _creation = true);
    try {
      User? user;
      try {
        user = (await FirebaseAuth.instance.createUserWithEmailAndPassword(email: e, password: p)).user;
      } on FirebaseAuthException catch (err) {
        if (err.code != 'email-already-in-use') rethrow;
        // Inscription commencée puis interrompue : on la reprend si c'est
        // bien la même personne (même mot de passe) et qu'elle n'est pas finie.
        try {
          user = (await FirebaseAuth.instance.signInWithEmailAndPassword(email: e, password: p)).user;
        } on FirebaseAuthException {
          throw FirebaseAuthException(code: 'deja-utilise-autre-mdp');
        }
        final dejaInscrit = user != null && await _compteDejaComplet(user.uid);
        if (dejaInscrit) {
          await FirebaseAuth.instance.signOut();
          throw FirebaseAuthException(code: 'deja-inscrit');
        }
      }
      if (user == null) throw FirebaseAuthException(code: 'inconnu');
      User_Info.uid = user.uid;
      if (!mounted) return;
      if (user.emailVerified) {
        _goNext();
        return;
      }
      // E-mail à valider AVANT de remplir le reste : écran d'attente.
      try { await user.sendEmailVerification(); } catch (_) {}
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => _ValidationEmailPage(email: e, suivante: widget.suivante)));
    } on FirebaseAuthException catch (err) {
      final m = switch (err.code) {
        'deja-inscrit' => 'Un compte existe déjà avec cet e-mail : connectez-vous depuis la page de connexion.',
        'deja-utilise-autre-mdp' => 'Cet e-mail est déjà utilisé. Connectez-vous ou réinitialisez votre mot de passe.',
        'invalid-email' => "Cet e-mail n'est pas valide.",
        'weak-password' => 'Mot de passe trop faible (6 caractères minimum).',
        'network-request-failed' => 'Pas de connexion internet. Réessayez.',
        _ => 'Création du compte impossible. Réessayez.',
      };
      if (mounted) setState(() => _erreur = m);
      if (FirebaseAuth.instance.currentUser == null) User_Info.inscriptionEnCours = false;
    } finally {
      if (mounted) setState(() => _creation = false);
    }
  }

  /// Compte déjà terminé (profil enregistré) : pas une inscription à reprendre.
  Future<bool> _compteDejaComplet(String uid) async {
    try {
      final r = await Supabase.instance.client.from('user_profiles').select('id').eq('uid', uid).limit(1);
      return (r as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      final cred = await signInWithGoogle();
      if (cred == null) return; // annulé par l'utilisateur
      // L'utilisateur Firebase existe déjà (authentifié à l'instant) — pas
      // de mot de passe à créer, l'email est déjà vérifié par Google : le
      // reste du parcours (CGU) saute directement à l'inscription finale.
      User_Info.uid   = cred.user!.uid;
      User_Info.email = cred.user!.email ?? '';
      if (!mounted) return;
      _goNext();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur de connexion Google : $e', style: const TextStyle(fontFamily: 'Galey'))),
      );
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  void _goNext() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => widget.suivante()));
  }

  @override
  Widget build(BuildContext context) {
    final isEleveur = User_Info.isElevage || User_Info.isPro;
    final isAsso = User_Info.isAssociation;
    final str = _strength(_passwordCtrl.text);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Inscription',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: _StepBar(current: 1, total: isEleveur || isAsso ? 4 : 3),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sécurité du compte',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                  fontSize: 20, color: Color(0xFF1F2A2E))),
          const SizedBox(height: 6),
          Text('Renseignez votre email et créez un mot de passe sécurisé.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 24),

          // ── Email ─────────────────────────────────────────────────────────────
          _card([
            _field(
              ctrl: _emailCtrl,
              label: 'Email',
              icon: Icons.email_outlined,
              keyboard: TextInputType.emailAddress,
              valid: _emailOk,
              error: 'Email invalide',
            ),
          ]),
          const SizedBox(height: 16),

          // ── Mot de passe ──────────────────────────────────────────────────────
          _card([
            _passField(
              ctrl: _passwordCtrl,
              label: 'Mot de passe',
              show: _showPass,
              valid: _passOk,
              error: 'Minimum 6 caractères',
              onToggle: () => setState(() => _showPass = !_showPass),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            // Barre de force
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: str / 5.0,
                minHeight: 4,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  str < 2 ? Colors.red : str < 4 ? const Color(0xFFE9A825) : _green,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              str < 2 ? 'Mot de passe faible'
                  : str < 4 ? 'Mot de passe moyen'
                  : 'Mot de passe fort',
              style: TextStyle(
                fontFamily: 'Galey', fontSize: 11,
                color: str < 2 ? Colors.red : str < 4 ? const Color(0xFFE9A825) : _green,
              ),
            ),
            const SizedBox(height: 14),
            _passField(
              ctrl: _verifCtrl,
              label: 'Confirmer le mot de passe',
              show: _showPass2,
              valid: _verifOk,
              error: 'Les mots de passe ne correspondent pas',
              onToggle: () => setState(() => _showPass2 = !_showPass2),
            ),
          ]),
          if (_erreur != null) ...[
            const SizedBox(height: 16),
            Text(_erreur!, style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: Color(0xFFB3261E), fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _creation ? null : _continue,
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(_creation ? 'CRÉATION DU COMPTE…' : 'CONTINUER',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 16, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: Divider(color: Colors.grey.shade300)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('ou', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            ),
            Expanded(child: Divider(color: Colors.grey.shade300)),
          ]),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _googleLoading ? null : _continueWithGoogle,
              icon: _googleLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Image.asset('assets/logo/google.png', width: 18, height: 18),
              label: const Text('Continuer avec Google',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1F2A2E))),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey.shade300),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Widget _card(List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
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
    void Function(String)? onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextFormField(
            controller: ctrl,
            keyboardType: keyboard,
            onChanged: onChanged,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
              prefixIcon: Icon(icon, size: 18, color: const Color(0xFF6F767B)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: valid ? const Color(0xFFE4E7E2) : Colors.red)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _green, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              isDense: true,
            ),
          ),
          if (!valid)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(error, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.red)),
            ),
        ]),
      );

  Widget _passField({
    required TextEditingController ctrl,
    required String label,
    required bool show,
    required VoidCallback onToggle,
    bool valid = true,
    String error = '',
    void Function(String)? onChanged,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextFormField(
          controller: ctrl,
          obscureText: !show,
          onChanged: onChanged,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
            prefixIcon: const Icon(Icons.lock_outline, size: 18, color: Color(0xFF6F767B)),
            suffixIcon: IconButton(
              icon: Icon(show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 18, color: const Color(0xFF6F767B)),
              onPressed: onToggle,
              padding: EdgeInsets.zero,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: valid ? const Color(0xFFE4E7E2) : Colors.red)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _green, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            isDense: true,
          ),
        ),
        if (!valid)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(error, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.red)),
          ),
      ]);
}

class _StepBar extends StatelessWidget {
  final int current;
  final int total;
  const _StepBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    child: Row(
      children: List.generate(total, (i) => Expanded(
        child: Container(
          height: 3,
          margin: EdgeInsets.only(right: i < total - 1 ? 4 : 0),
          decoration: BoxDecoration(
            color: i < current ? Colors.white : Colors.white38,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      )),
    ),
  );
}

/// Inscription : e-mail à valider avant les étapes d'informations. Vérifie
/// seul toutes les 4 s (lien cliqué depuis la boîte mail), ou sur « J'ai validé ».
class _ValidationEmailPage extends StatefulWidget {
  final String email;
  final Widget Function() suivante;
  const _ValidationEmailPage({required this.email, required this.suivante});
  @override
  State<_ValidationEmailPage> createState() => _ValidationEmailPageState();
}

class _ValidationEmailPageState extends State<_ValidationEmailPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  Timer? _timer;
  bool _verif = false, _envoi = false, _fini = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _verifier(silencieux: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _verifier({bool silencieux = false}) async {
    if (_verif || _fini) return;
    if (!silencieux) setState(() { _verif = true; _message = null; });
    try {
      final u = FirebaseAuth.instance.currentUser;
      await u?.reload();
      final ok = FirebaseAuth.instance.currentUser?.emailVerified ?? false;
      if (ok && mounted && !_fini) {
        _fini = true;
        _timer?.cancel();
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => widget.suivante()));
        return;
      }
      if (!silencieux && mounted) {
        setState(() => _message = "L'adresse n'est pas encore validée : ouvrez le lien reçu par e-mail.");
      }
    } catch (_) {
      if (!silencieux && mounted) setState(() => _message = 'Vérification impossible. Réessayez.');
    } finally {
      if (!silencieux && mounted) setState(() => _verif = false);
    }
  }

  Future<void> _renvoyer() async {
    setState(() { _envoi = true; _message = null; });
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted) setState(() => _message = 'E-mail renvoyé. Pensez à regarder dans les indésirables.');
    } catch (_) {
      if (mounted) setState(() => _message = 'Trop de demandes : patientez une minute avant de renvoyer.');
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
          title: const Text('Validez votre e-mail', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.mark_email_unread_outlined, size: 56, color: _teal),
        const SizedBox(height: 16),
        const Text('Votre compte est créé', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20)),
        const SizedBox(height: 10),
        Text("Nous avons envoyé un lien de validation à ${widget.email}. Ouvrez-le, puis revenez ici : la suite de l'inscription s'ouvre toute seule.",
            textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', fontSize: 14.5, color: Colors.grey.shade700, height: 1.5)),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _verif ? null : () => _verifier(),
          style: FilledButton.styleFrom(backgroundColor: _green, padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: Text(_verif ? 'Vérification…' : "J'ai validé mon e-mail",
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        const SizedBox(height: 10),
        TextButton(onPressed: _envoi ? null : _renvoyer,
            child: Text(_envoi ? 'Envoi…' : "Renvoyer l'e-mail", style: const TextStyle(fontFamily: 'Galey', color: _teal))),
        TextButton(
          onPressed: () async {
            // Mauvaise adresse : on supprime le compte tout juste créé et on corrige.
            try { await FirebaseAuth.instance.currentUser?.delete(); } catch (_) {}
            try { await FirebaseAuth.instance.signOut(); } catch (_) {}
            User_Info.inscriptionEnCours = false;
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text("Modifier l'adresse e-mail", style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
        ),
        if (_message != null) ...[
          const SizedBox(height: 10),
          Text(_message!, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: Color(0xFFB3261E))),
        ],
      ]),
    );
  }
}
