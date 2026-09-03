import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Accès privé pendant la phase de test : un mot de passe partagé est demandé
/// au premier lancement. Une fois validé, l'accès est mémorisé sur l'appareil
/// (comme le cookie `beta_access` du site).
///
/// Le mot de passe de référence est lu dans Supabase (`app_config` ->
/// `beta_password`) pour pouvoir être changé sans republier l'app ; en cas
/// d'échec réseau on retombe sur [kBetaPassword] compilé dans l'app.
class BetaGate extends StatefulWidget {
  final Widget child;
  const BetaGate({super.key, required this.child});

  static const _prefsKey = 'beta_gate_unlocked_v1';

  /// Efface l'accès mémorisé (utile pour retester le portail).
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  @override
  State<BetaGate> createState() => _BetaGateState();
}

class _BetaGateState extends State<BetaGate> {
  bool _checking = true;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (!kBetaGateEnabled) {
      setState(() {
        _unlocked = true;
        _checking = false;
      });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _unlocked = prefs.getBool(BetaGate._prefsKey) ?? false;
      _checking = false;
    });
  }

  Future<void> _onUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(BetaGate._prefsKey, true);
    if (mounted) setState(() => _unlocked = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8F8F6),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_unlocked) return widget.child;
    return _BetaGatePage(onUnlocked: _onUnlocked);
  }
}

class _BetaGatePage extends StatefulWidget {
  final Future<void> Function() onUnlocked;
  const _BetaGatePage({required this.onUnlocked});

  @override
  State<_BetaGatePage> createState() => _BetaGatePageState();
}

class _BetaGatePageState extends State<_BetaGatePage> {
  final _controller = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Mot de passe de référence : Supabase d'abord, sinon la constante compilée.
  Future<String> _referencePassword() async {
    try {
      final row = await Supabase.instance.client
          .from('app_config')
          .select('value')
          .eq('key', 'beta_password')
          .maybeSingle()
          .timeout(const Duration(seconds: 6));
      final remote = (row?['value'] as String?)?.trim() ?? '';
      if (remote.isNotEmpty) return remote;
    } catch (_) {
      // hors ligne ou table absente → on utilise la constante
    }
    return kBetaPassword;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    final entered = _controller.text.trim();
    final reference = await _referencePassword();
    if (entered.isNotEmpty && entered == reference) {
      await widget.onUnlocked();
    } else {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Mot de passe incorrect.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF0C5C6C);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFEDEDED)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/Logo_petsmatch_fond_blanc.png',
                      width: 76,
                      height: 76,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.pets, size: 60, color: teal),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Accès bêta privé',
                      style: TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2A2E),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "L'application est en accès restreint.\nEntrez le mot de passe pour continuer.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: Color(0xFF6B7280), height: 1.4),
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: _controller,
                      obscureText: _obscure,
                      autofocus: true,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _loading ? null : _submit(),
                      decoration: InputDecoration(
                        hintText: 'Mot de passe',
                        filled: true,
                        fillColor: const Color(0xFFF8F8F6),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: teal, width: 2),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: const Color(0xFF9CA3AF),
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!,
                          style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13)),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                "Accéder à l'application",
                                style: TextStyle(
                                    fontFamily: 'Galey',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
