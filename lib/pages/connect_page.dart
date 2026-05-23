import 'package:PetsMatch/pages/inscription_main.dart';
import 'package:PetsMatch/pages/login_page.dart';
import 'package:flutter/material.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _bg = Color(0xFFF8F8F6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          // ── En-tête teal ──────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            color: _teal,
            padding: EdgeInsets.fromLTRB(
                24, MediaQuery.of(context).padding.top + 32, 24, 32),
            child: Column(children: [
              Image.asset(
                'assets/Banniere_petsmatch.png',
                width: double.infinity,
                height: 110,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 12),
              const Text(
                'Connecter · Prendre soin · Partager',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 14,
                    color: Colors.white70),
              ),
            ]),
          ),

          // ── Corps ─────────────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Bienvenue',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w700,
                        fontSize: 26,
                        color: Color(0xFF1F2A2E)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Rejoignez la communauté des passionnés d\'animaux.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 14,
                        color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 40),

                  // Bouton Se connecter
                  ElevatedButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const LoginPage())),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Text('SE CONNECTER',
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Colors.white)),
                  ),
                  const SizedBox(height: 14),

                  // Bouton S'inscrire
                  OutlinedButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const InscriptionChoicePage())),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _green, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text("S'INSCRIRE",
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: _green)),
                  ),

                  const SizedBox(height: 32),
                  Row(children: [
                    Expanded(
                        child: Divider(color: Colors.grey.shade300, height: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('ou',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 13,
                              color: Colors.grey.shade400)),
                    ),
                    Expanded(
                        child: Divider(color: Colors.grey.shade300, height: 1)),
                  ]),
                  const SizedBox(height: 24),

                  // Infos rapides
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _InfoChip(icon: Icons.pets, label: 'Éleveurs certifiés'),
                      _InfoChip(icon: Icons.verified_outlined, label: 'Annonces vérifiées'),
                      _InfoChip(icon: Icons.favorite_border, label: 'Communauté'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F0E4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 22, color: const Color(0xFF6E9E57)),
      ),
      const SizedBox(height: 6),
      SizedBox(
        width: 90,
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Galey',
                fontSize: 11,
                color: Colors.grey.shade600)),
      ),
    ]);
  }
}
