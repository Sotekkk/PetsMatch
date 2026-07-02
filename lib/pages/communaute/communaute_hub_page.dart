import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/pages/promenades/promenades_page.dart';
import 'package:PetsMatch/pages/communaute/forum_page.dart';
import 'package:PetsMatch/pages/communaute/groupes_page.dart';
import 'package:PetsMatch/pages/evenements/evenements_page.dart';
import 'package:PetsMatch/pages/lieux/lieux_pet_friendly_page.dart';
import 'package:PetsMatch/pages/nature/natural_places_page.dart';
import 'package:PetsMatch/pages/petfriends/petfriends_page.dart';
import 'package:PetsMatch/pages/connect_page.dart';
import 'package:url_launcher/url_launcher.dart';

const _teal = Color(0xFF0C5C6C);
const _bg = Color(0xFFF8F8F8);

class CommunauteHubPage extends StatelessWidget {
  const CommunauteHubPage({super.key});

  static const _sections = <_CommunauteSection>[
    _CommunauteSection(
      icon: Icons.directions_walk_outlined,
      label: 'Balades canines',
      subtitle: 'Organisez des sorties avec d\'autres propriétaires',
      color: Color(0xFF2E7D5E),
      requiresAuth: false,
    ),
    _CommunauteSection(
      icon: Icons.forum_outlined,
      label: 'Forums',
      subtitle: 'Échangez avec la communauté PetsMatch',
      color: Color(0xFF0C5C6C),
      requiresAuth: false,
    ),
    _CommunauteSection(
      icon: Icons.groups_outlined,
      label: 'Groupes',
      subtitle: 'Rejoignez des groupes par race ou activité',
      color: Color(0xFF6A1B9A),
      requiresAuth: false,
    ),
    _CommunauteSection(
      icon: Icons.event_outlined,
      label: 'Événements',
      subtitle: 'Expositions, concours & rencontres',
      color: Color(0xFFE65100),
      requiresAuth: false,
    ),
    _CommunauteSection(
      icon: Icons.location_on_outlined,
      label: 'Lieux Pet-Friendly',
      subtitle: 'Restaurants, hôtels & parcs qui accueillent vos animaux',
      color: Color(0xFFF57C00),
      requiresAuth: false,
    ),
    _CommunauteSection(
      icon: Icons.forest_outlined,
      label: 'Lieux Naturels',
      subtitle: 'Plages, lacs, parcs & forêts accessibles avec vos animaux',
      color: Color(0xFF2E7D32),
      requiresAuth: false,
    ),
    _CommunauteSection(
      icon: Icons.people_outline,
      label: 'PetFriends',
      subtitle: 'Votre réseau de passionnés d\'animaux',
      color: Color(0xFFAD1457),
      requiresAuth: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: canPop
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  )
                : null,
            title: const Text(
              'Communauté',
              style: TextStyle(
                  fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero banner
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _teal,
                        const Color(0xFF1E7A8C),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rejoignez la communauté',
                              style: TextStyle(
                                  fontFamily: 'Galey',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: Colors.white),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Partagez, échangez et créez des liens avec des passionnés comme vous.',
                              style: TextStyle(
                                  fontFamily: 'Galey',
                                  fontSize: 13,
                                  color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.pets,
                            color: Colors.white, size: 30),
                      ),
                    ],
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 28, 16, 12),
                  child: Text(
                    'Explorer',
                    style: TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: Color(0xFF1E2025)),
                  ),
                ),

                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _sections.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) => _SectionCard(
                    section: _sections[i],
                    onTap: () => _navigate(ctx, _sections[i]),
                  ),
                ),

                const SizedBox(height: 16),

                // ── SOS Maltraitance ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _SosMaltraitanceCard(),
                ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _navigate(BuildContext context, _CommunauteSection section) {
    final isLoggedIn =
        FirebaseAuth.instance.currentUser != null;

    if (section.requiresAuth && !isLoggedIn) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => const _LoginPromptSheet(),
      );
      return;
    }

    Widget page;
    switch (section.label) {
      case 'Balades canines':
        page = const PromenadePage();
        break;
      case 'Forums':
        page = const ForumPage();
        break;
      case 'Groupes':
        page = const GroupesPage();
        break;
      case 'Événements':
        page = const EvenementsPage();
        break;
      case 'Lieux Pet-Friendly':
        page = const LieuxPetFriendlyPage();
        break;
      case 'Lieux Naturels':
        page = const NaturalPlacesPage();
        break;
      case 'PetFriends':
        page = const PetFriendsPage();
        break;
      default:
        return;
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _CommunauteSection {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final bool requiresAuth;

  const _CommunauteSection({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.requiresAuth,
  });
}

class _SectionCard extends StatelessWidget {
  final _CommunauteSection section;
  final VoidCallback onTap;

  const _SectionCard({required this.section, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: section.color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(section.icon, color: section.color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(section.label,
                          style: const TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Color(0xFF1E2025))),
                      if (section.requiresAuth) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.lock_outline,
                              size: 11, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(section.subtitle,
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 12,
                          color: Colors.grey.shade500)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

// ── Login prompt (bottom sheet) ───────────────────────────────────────────────

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
                  borderRadius: BorderRadius.circular(2)),
            ),
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
            Text(
              'Connectez-vous pour accéder à cette fonctionnalité.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontSize: 14,
                  color: Colors.grey.shade600),
            ),
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

// ── SOS Maltraitance card ─────────────────────────────────────────────────────

class _SosMaltraitanceCard extends StatelessWidget {
  const _SosMaltraitanceCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCE4EC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFC62828).withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFC62828).withValues(alpha: 0.10),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFC62828), size: 18),
              SizedBox(width: 8),
              Text('Signalement maltraitance animale',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFFC62828))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(children: [
              const Icon(Icons.phone_outlined, size: 16, color: Color(0xFFC62828)),
              const SizedBox(width: 8),
              const Text('3677',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFFC62828))),
              const SizedBox(width: 6),
              Expanded(
                child: Text('— SOS Maltraitance Animale',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade700)),
              ),
              GestureDetector(
                onTap: () async {
                  try {
                    await launchUrl(Uri(scheme: 'tel', path: '3677'),
                        mode: LaunchMode.externalApplication);
                  } catch (_) {}
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC62828),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Appeler',
                      style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
            ]),
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
              child: const Row(children: [
                Icon(Icons.open_in_new_rounded, size: 13, color: Color(0xFF0C5C6C)),
                SizedBox(width: 6),
                Text('Formulaire de signalement en ligne',
                    style: TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0C5C6C),
                        decoration: TextDecoration.underline)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
