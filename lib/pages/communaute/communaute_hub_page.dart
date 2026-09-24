import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:PetsMatch/pages/promenades/promenades_page.dart';
import 'package:PetsMatch/pages/communaute/forum_page.dart';
import 'package:PetsMatch/pages/evenements/evenements_page.dart';
import 'package:PetsMatch/pages/explorer/explorer_page.dart';
import 'package:PetsMatch/pages/connect_page.dart';
import 'package:PetsMatch/pages/balades_ludiques/balades_ludiques_hub_page.dart';
import 'package:url_launcher/url_launcher.dart';

const _teal = Color(0xFF0C5C6C);
const _darkC = Color(0xFF071C22);
const _bgGrad = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF071C22), Color(0xFF0C3535), Color(0xFF0C3520)],
  stops: [0.0, 0.5, 1.0],
);

// ─── Sections ─────────────────────────────────────────────────────────────────

class _CommunauteSection {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final List<String> tags;

  const _CommunauteSection({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    this.tags = const [],
  });
}

const _sections = <_CommunauteSection>[
  _CommunauteSection(
    icon: Icons.people_alt_outlined,
    label: 'PetFriends',
    subtitle: 'Le réseau social des passionnés d\'animaux',
    color: Color(0xFFFF5DA2),
    tags: ['Fil d\'actualité', 'Groupes', 'Forums', 'Amis', 'Badges'],
  ),
  _CommunauteSection(
    icon: Icons.pets_outlined,
    label: 'Balades & Rencontres',
    subtitle: 'Organisez ou rejoignez des sorties avec la communauté',
    color: Color(0xFF7ED69D),
    tags: ['Autour de moi', 'Créer une balade', 'Événements'],
  ),
  _CommunauteSection(
    icon: Icons.explore_outlined,
    label: 'Balades ludiques',
    subtitle: 'Parcours, défis et chasses au trésor avec votre animal',
    color: Color(0xFFFFD166),
    tags: ['Parcours', 'Défis', 'Badges', 'Classements'],
  ),
  _CommunauteSection(
    icon: Icons.location_on_outlined,
    label: 'Explorer',
    subtitle: 'Découvrez les meilleurs endroits avec vos animaux',
    color: Color(0xFF9D8DF1),
    tags: ['Nature', 'Pet-Friendly', 'Activités'],
  ),
  _CommunauteSection(
    icon: Icons.event_outlined,
    label: 'Événements',
    subtitle: 'Expositions, concours & rencontres',
    color: Color(0xFFFF9F68),
    tags: ['Expositions', 'Concours', 'Rencontres'],
  ),
];

// ─── Page principale ──────────────────────────────────────────────────────────

class CommunauteHubPage extends StatelessWidget {
  const CommunauteHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.isFirst == false;

    return Scaffold(
      backgroundColor: _darkC,
      body: Container(
        decoration: const BoxDecoration(gradient: _bgGrad),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // ── Header sur fond sombre ───────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (canPop)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.25)),
                                  ),
                                  child: const Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                      color: Colors.white,
                                      size: 18),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const Column(
                        children: [
                          Text('Communauté',
                              style: TextStyle(
                                  fontFamily: 'Galey',
                                  fontWeight: FontWeight.w800,
                                  fontSize: 26,
                                  color: Colors.white)),
                          SizedBox(height: 4),
                          Text('Tout un monde à partager avec vos animaux ',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontFamily: 'Galey',
                                  fontSize: 12,
                                  color: Colors.white60)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ── Hero + Cards + SOS dans un seul sliver (z-order garanti) ──
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    // Image avec arc en haut
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ClipPath(
                        clipper: const _TopArcClipper(arcHeight: 32),
                        child: SizedBox(
                          height: 240,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset(
                                'assets/deco/communautybackground.jpg',
                                fit: BoxFit.cover,
                                alignment: Alignment.center,
                              ),
                              Positioned(
                                bottom: 0, left: 0, right: 0, height: 90,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Colors.transparent, _darkC],
                                    ),
                                  ),
                                ),
                              ),
                              // Brushstroke peint en CustomPaint
                              Positioned(
                                right: -32, top: 22,
                                width: 234, height: 178,
                                child: Opacity(
                                  opacity: 0.54,
                                  child: CustomPaint(
                                    painter: _BrushstrokePainter(),
                                  ),
                                ),
                              ),
                              // Texte avec légère inclinaison
                              Positioned(
                                right: 0, top: 38,
                                width: 220, height: 158,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Transform.rotate(
                                      angle: -0.06,
                                      child: Padding(
                                        padding: const EdgeInsets.only(left: 28),
                                        child: const Column(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Text('Des rencontres',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(fontFamily: 'Galey',
                                                    fontWeight: FontWeight.w800,
                                                    fontStyle: FontStyle.italic,
                                                    fontSize: 15, color: Colors.white)),
                                            Text('des lieux, des activités',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(fontFamily: 'Galey',
                                                    fontWeight: FontWeight.w800,
                                                    fontStyle: FontStyle.italic,
                                                    fontSize: 15, color: Colors.white)),
                                            Text('et bien plus encore !',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(fontFamily: 'Galey',
                                                    fontWeight: FontWeight.w800,
                                                    fontStyle: FontStyle.italic,
                                                    fontSize: 15, color: Colors.white)),
                                            SizedBox(height: 6),
                                            Icon(Icons.pets,
                                                color: Colors.white70, size: 20),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Cards — peintes APRÈS l'image donc forcément par-dessus
                    Transform.translate(
                      offset: const Offset(0, -28),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        child: Column(
                          children: [
                            for (int i = 0; i < _sections.length; i++) ...[
                              _SectionCard(
                                  section: _sections[i],
                                  onTap: () => _navigate(context, _sections[i])),
                              if (i < _sections.length - 1)
                                const SizedBox(height: 10),
                            ],
                            const SizedBox(height: 20),
                            const _SosMaltraitanceCard(),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _navigate(BuildContext context, _CommunauteSection section) {
    Widget page;
    switch (section.label) {
      case 'PetFriends':
        page = const ForumPage();
        break;
      case 'Balades & Rencontres':
        page = const PromenadePage();
        break;
      case 'Balades ludiques':
        page = const BaladesLudiquesHubPage();
        break;
      case 'Explorer':
        page = const ExplorerPage();
        break;
      case 'Événements':
        page = const EvenementsPage();
        break;
      default:
        return;
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final _CommunauteSection section;
  final VoidCallback onTap;
  const _SectionCard({required this.section, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
              section.color.withValues(alpha: 0.10), const Color(0xFFF9FBF9)),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: section.color.withValues(alpha: 0.30), width: 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Color.alphaBlend(section.color.withValues(alpha: 0.45),
                    const Color(0xFFF9FBF9)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Stack(alignment: Alignment.center, children: [
                Icon(section.icon, color: Colors.black.withValues(alpha: 0.28), size: 31),
                Icon(section.icon, color: section.color, size: 26),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(section.label,
                      style: const TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Color(0xFF1A1A1A))),
                  const SizedBox(height: 3),
                  Text(section.subtitle,
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 12,
                          color: Colors.grey.shade600)),
                  if (section.tags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(section.tags.join(' • '),
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 11,
                            color: Colors.grey.shade400),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 13, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

// ── Login prompt ──────────────────────────────────────────────────────────────

class _LoginPromptSheet extends StatelessWidget {
  const _LoginPromptSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Icon(Icons.lock_outline, size: 40, color: _teal),
            const SizedBox(height: 14),
            const Text('Connexion requise',
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: Color(0xFF1E2025))),
            const SizedBox(height: 8),
            Text('Connectez-vous pour accéder à cette fonctionnalité.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 14,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: _teal,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => WelcomePage()));
                },
                child: const Text('Se connecter',
                    style: TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── SOS Maltraitance ──────────────────────────────────────────────────────────

class _SosMaltraitanceCard extends StatelessWidget {
  const _SosMaltraitanceCard();
  static const _red = Color(0xFFC93B4B);
  static const _btnRed = Color(0xFFD9383E);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF2D3D7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _red.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFFC93B4B), Color(0xFFD9383E)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Signalement maltraitance animale',
                    style: TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.white)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(
              children: [
                const Icon(Icons.phone_outlined, size: 16, color: _red),
                const SizedBox(width: 8),
                const Text('3677',
                    style: TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _red)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('— SOS Maltraitance Animale',
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 12,
                          color: Colors.grey.shade600)),
                ),
                GestureDetector(
                  onTap: () async {
                    try {
                      await launchUrl(Uri(scheme: 'tel', path: '3677'),
                          mode: LaunchMode.externalApplication);
                    } catch (_) {}
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: _btnRed,
                        borderRadius: BorderRadius.circular(20)),
                    child: const Text('Appeler',
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
            child: GestureDetector(
              onTap: () async {
                try {
                  await launchUrl(
                      Uri.parse('https://3677.fr/formulaire-de-signalement'),
                      mode: LaunchMode.externalApplication);
                } catch (_) {}
              },
              child: const Row(
                children: [
                  Icon(Icons.open_in_new_rounded, size: 13, color: _teal),
                  SizedBox(width: 6),
                  Text('Formulaire de signalement en ligne',
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _teal,
                          decoration: TextDecoration.underline,
                          decorationColor: _teal)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Arc clipper ───────────────────────────────────────────────────────────────

class _TopArcClipper extends CustomClipper<Path> {
  final double arcHeight;
  const _TopArcClipper({this.arcHeight = 32});

  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(0, arcHeight)
      ..quadraticBezierTo(size.width / 2, 0, size.width, arcHeight)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant _TopArcClipper old) => old.arcHeight != arcHeight;
}

// ── Brushstroke painter ───────────────────────────────────────────────────────

class _BrushstrokePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final shader = const LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [Color(0xFF071C22), Color(0xFF0C3535), Color(0xFF0C3520)],
      stops: [0.0, 0.5, 1.0],
    ).createShader(Rect.fromLTWH(0, 0, w, h));

    final fill = Paint()
      ..shader = shader
      ..style = PaintingStyle.fill;

    final edge = Paint()
      ..shader = shader
      ..style = PaintingStyle.fill;

    // Corps principal — resserré en haut et en bas
    final body = Path()
      ..moveTo(w * 0.10, h * 0.42)
      ..cubicTo(w * 0.04, h * 0.32, w * 0.10, h * 0.18, w * 0.24, h * 0.14)
      ..cubicTo(w * 0.38, h * 0.10, w * 0.55, h * 0.14, w * 0.70, h * 0.12)
      ..cubicTo(w * 0.83, h * 0.10, w * 0.97, h * 0.16, w * 0.99, h * 0.26)
      ..cubicTo(w * 1.01, h * 0.36, w * 0.96, h * 0.48, w * 0.94, h * 0.56)
      ..cubicTo(w * 0.92, h * 0.64, w * 0.97, h * 0.72, w * 0.91, h * 0.79)
      ..cubicTo(w * 0.84, h * 0.87, w * 0.70, h * 0.90, w * 0.55, h * 0.88)
      ..cubicTo(w * 0.40, h * 0.86, w * 0.26, h * 0.91, w * 0.14, h * 0.85)
      ..cubicTo(w * 0.02, h * 0.78, -w * 0.01, h * 0.64, w * 0.02, h * 0.52)
      ..cubicTo(w * 0.05, h * 0.46, w * 0.14, h * 0.48, w * 0.10, h * 0.42)
      ..close();
    canvas.drawPath(body, fill);

    // Bavures haut-gauche
    final b1 = Path()
      ..moveTo(w * 0.16, h * 0.17)
      ..cubicTo(w * 0.08, h * 0.10, w * 0.02, h * 0.06, w * 0.06, h * 0.12)
      ..cubicTo(w * 0.09, h * 0.15, w * 0.13, h * 0.15, w * 0.16, h * 0.17)
      ..close();
    canvas.drawPath(b1, edge);

    // Bavures haut-droit
    final b2 = Path()
      ..moveTo(w * 0.76, h * 0.13)
      ..cubicTo(w * 0.82, h * 0.05, w * 0.92, h * 0.08, w * 0.86, h * 0.14)
      ..cubicTo(w * 0.82, h * 0.16, w * 0.78, h * 0.15, w * 0.76, h * 0.13)
      ..close();
    canvas.drawPath(b2, edge);

    // Bavures bord droit
    final b3 = Path()
      ..moveTo(w * 0.97, h * 0.40)
      ..cubicTo(w * 1.06, h * 0.35, w * 1.08, h * 0.46, w * 1.00, h * 0.48)
      ..cubicTo(w * 0.97, h * 0.48, w * 0.96, h * 0.44, w * 0.97, h * 0.40)
      ..close();
    canvas.drawPath(b3, edge);

    // Bavures bas
    final b4 = Path()
      ..moveTo(w * 0.42, h * 0.89)
      ..cubicTo(w * 0.40, h * 0.97, w * 0.50, h * 0.98, w * 0.52, h * 0.90)
      ..cubicTo(w * 0.50, h * 0.87, w * 0.44, h * 0.87, w * 0.42, h * 0.89)
      ..close();
    canvas.drawPath(b4, edge);

    // Éclaboussure bas-gauche
    final b5 = Path()
      ..moveTo(w * 0.06, h * 0.80)
      ..cubicTo(-w * 0.01, h * 0.84, -w * 0.02, h * 0.76, w * 0.04, h * 0.76)
      ..cubicTo(w * 0.07, h * 0.76, w * 0.08, h * 0.78, w * 0.06, h * 0.80)
      ..close();
    canvas.drawPath(b5, edge);

    // Splatter dots
    final dot = Paint()
      ..shader = shader
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.92, h * 0.18), w * 0.022, dot);
    canvas.drawCircle(Offset(w * 0.04, h * 0.24), w * 0.014, dot);
    canvas.drawCircle(Offset(w * 0.56, h * 0.94), w * 0.016, dot);
    canvas.drawCircle(Offset(w * 1.03, h * 0.58), w * 0.012, dot);
    canvas.drawCircle(Offset(w * 0.18, h * 0.94), w * 0.010, dot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
