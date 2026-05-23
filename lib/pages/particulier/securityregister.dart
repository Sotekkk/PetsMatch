import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/info_elevage.dart';
import 'package:PetsMatch/pages/particulier/description_page.dart';
import 'package:flutter/material.dart';

class RegisterSecurity extends StatefulWidget {
  const RegisterSecurity({super.key});
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

  void _continue() {
    final e = _emailCtrl.text.trim();
    final p = _passwordCtrl.text;
    final v = _verifCtrl.text;
    setState(() {
      _emailOk = e.isNotEmpty && e.contains('@');
      _passOk  = p.length >= 6;
      _verifOk = v == p && v.isNotEmpty;
    });
    if (!_emailOk || !_passOk || !_verifOk) return;

    User_Info.email    = e;
    User_Info.password = p;
    final isEleveur = User_Info.isElevage || User_Info.isPro;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isEleveur
            ? const RegisterElevageInformation()
            : DescriptionRegistrationPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEleveur = User_Info.isElevage || User_Info.isPro;
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
          child: _StepBar(current: isEleveur ? 2 : 3, total: isEleveur ? 4 : 3),
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
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _continue,
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('CONTINUER',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 16, color: Colors.white)),
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
