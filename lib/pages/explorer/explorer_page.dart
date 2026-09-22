import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:PetsMatch/pages/lieux/lieux_pet_friendly_page.dart';
import 'package:PetsMatch/pages/nature/natural_places_page.dart';

// ─── Constantes DA ────────────────────────────────────────────────────────────

const _darkC = Color(0xFF071C22);
const _bgGrad = LinearGradient(
  begin: Alignment.topCenter, end: Alignment.bottomCenter,
  colors: [Color(0xFF071C22), Color(0xFF0C3535), Color(0xFF0C3520)],
  stops: [0.0, 0.5, 1.0],
);

// ─── Modèle catégorie ─────────────────────────────────────────────────────────

class _ExplorerCategory {
  final IconData icon;
  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final Widget page;

  const _ExplorerCategory({
    required this.icon,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.page,
  });
}

final _categories = [
  _ExplorerCategory(
    icon: Icons.forest_outlined,
    emoji: '🌳',
    title: 'Nature',
    subtitle: 'Plages · Forêts · Lacs · Randonnées · Parcs · Parcs canins',
    color: const Color(0xFF2E9E72),
    page: const NaturalPlacesPage(),
  ),
  _ExplorerCategory(
    icon: Icons.location_on_outlined,
    emoji: '🏨',
    title: 'Pet-Friendly',
    subtitle: 'Hôtels · Gîtes · Campings · Restaurants · Cafés · Commerces',
    color: const Color(0xFFE8A020),
    page: const LieuxPetFriendlyPage(),
  ),
  _ExplorerCategory(
    icon: Icons.sports_outlined,
    emoji: '🎯',
    title: 'Activités',
    subtitle: 'Loisirs · Parcours · Activités accessibles aux animaux',
    color: const Color(0xFF9B6AD4),
    page: const LieuxPetFriendlyPage(), // TODO: page Activités dédiée
  ),
];

// ─── Page principale ──────────────────────────────────────────────────────────

class ExplorerPage extends StatelessWidget {
  const ExplorerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.isFirst == false;
    return Scaffold(
      backgroundColor: _darkC,
      body: Stack(children: [
        Positioned.fill(child: Container(decoration: const BoxDecoration(gradient: _bgGrad))),
        SafeArea(child: CustomScrollView(slivers: [
          // ── Header ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(children: [
                if (canPop) ...[
                  GestureDetector(
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
                            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Explorer',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                            fontSize: 28, color: Colors.white)),
                    SizedBox(height: 2),
                    Text('Découvrez les meilleurs endroits avec vos animaux',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                            color: Color(0xFFADD8E6))),
                  ]),
                ),
              ]),
            ),
          ),

          // ── Carte "Autour de moi" ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NaturalPlacesPage())),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0C5C6C), Color(0xFF1E7A8C)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(children: [
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('📍 Autour de moi',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                              fontSize: 16, color: Colors.white)),
                      SizedBox(height: 5),
                      Text('Trouvez des lieux proches de votre position actuelle',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white70)),
                    ])),
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.near_me_outlined, color: Colors.white, size: 26),
                    ),
                  ]),
                ),
              ),
            ),
          ),

          // ── Titre section ──
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Text('Catégories',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 17, color: Colors.white)),
            ),
          ),

          // ── Catégories ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  if (i.isOdd) return const SizedBox(height: 12);
                  final cat = _categories[i ~/ 2];
                  return _CategoryCard(category: cat);
                },
                childCount: _categories.length * 2 - 1,
              ),
            ),
          ),
        ])),
      ]),
    );
  }
}

// ─── Carte catégorie ──────────────────────────────────────────────────────────

class _CategoryCard extends StatelessWidget {
  final _ExplorerCategory category;
  const _CategoryCard({required this.category});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => category.page)),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          // Icône
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: category.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(category.emoji, style: const TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(width: 14),
          // Texte
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(category.title,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                    fontSize: 16, color: Colors.black87)),
            const SizedBox(height: 4),
            Text(category.subtitle,
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ])),
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey.shade400),
        ]),
      ),
    );
  }
}
