import 'package:flutter/material.dart';

class VeterinairesPag extends StatelessWidget {
  const VeterinairesPag({super.key});

  @override
  Widget build(BuildContext context) {
    return _ServiceSubPage(
      title: 'Vétérinaires',
      icon: Icons.local_hospital_outlined,
      iconColor: const Color(0xFF6E9E57),
      headerColor: const Color(0xFF6E9E57),
      sections: const [
        _Section(
          icon: Icons.list_alt_outlined,
          title: 'Annuaire',
          description: 'Trouvez un vétérinaire près de chez vous',
        ),
        _Section(
          icon: Icons.star_outline,
          title: 'Avis & évaluations',
          description: 'Consultez les avis de la communauté',
        ),
        _Section(
          icon: Icons.emergency_outlined,
          title: 'Urgences',
          description: 'Vétérinaires disponibles 24h/24',
        ),
      ],
    );
  }
}

class EducationPage extends StatelessWidget {
  const EducationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _ServiceSubPage(
      title: 'Éducation & Garde',
      icon: Icons.volunteer_activism_outlined,
      iconColor: const Color(0xFFEF6C00),
      headerColor: const Color(0xFFEF6C00),
      sections: const [
        _Section(
          icon: Icons.psychology_outlined,
          title: 'Éducateurs / Comportementalistes',
          description: 'Professionnels certifiés en éducation et comportement animal',
        ),
        _Section(
          icon: Icons.tips_and_updates_outlined,
          title: 'Conseils pratiques',
          description: 'Guides et tutoriels pour votre animal',
        ),
        _Section(
          icon: Icons.directions_walk_outlined,
          title: 'Pet sitter / Promeneurs',
          description: 'Garde à domicile et promenades pour votre animal',
        ),
        _Section(
          icon: Icons.house_outlined,
          title: 'Pension pour animaux',
          description: 'Hébergement et garderie lors de vos absences',
        ),
      ],
    );
  }
}

class SantePage extends StatelessWidget {
  const SantePage({super.key});

  @override
  Widget build(BuildContext context) {
    return _ServiceSubPage(
      title: 'Santé',
      icon: Icons.favorite_outline,
      iconColor: const Color(0xFFE91E63),
      headerColor: const Color(0xFFE91E63),
      sections: const [
        _Section(
          icon: Icons.self_improvement_outlined,
          title: 'Ostéopathes',
          description: 'Ostéopathie animale — chiens, chats, chevaux et NAC',
        ),
        _Section(
          icon: Icons.accessibility_new_outlined,
          title: 'Kinésithérapeutes',
          description: 'Rééducation, mobilité et récupération post-opératoire',
        ),
        _Section(
          icon: Icons.eco_outlined,
          title: 'Naturopathes',
          description: 'Médecine naturelle, phytothérapie et aromathérapie',
        ),
        _Section(
          icon: Icons.spa_outlined,
          title: 'Acupuncteurs',
          description: 'Acupuncture et médecines alternatives pour animaux',
        ),
        _Section(
          icon: Icons.psychology_alt_outlined,
          title: 'Homéopathes',
          description: 'Traitements homéopathiques adaptés à votre animal',
        ),
        _Section(
          icon: Icons.biotech_outlined,
          title: 'Autres thérapeutes',
          description: 'Chiropracteurs, magnétiseurs, énergéticiens animaux',
        ),
      ],
    );
  }
}

class LieuxSympasPage extends StatelessWidget {
  const LieuxSympasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _ServiceSubPage(
      title: 'Animal Friendly',
      icon: Icons.park_outlined,
      iconColor: const Color(0xFF1E88E5),
      headerColor: const Color(0xFF1E88E5),
      sections: const [
        _Section(
          icon: Icons.grass_outlined,
          title: 'Parcs & espaces verts',
          description: 'Aires de jeux et balades avec votre animal',
        ),
        _Section(
          icon: Icons.restaurant_menu_outlined,
          title: 'Cafés & restaurants',
          description: 'Établissements acceptant les animaux',
        ),
        _Section(
          icon: Icons.hotel_outlined,
          title: 'Hôtels & hébergements',
          description: 'Séjours pet-friendly partout en France',
        ),
        _Section(
          icon: Icons.event_outlined,
          title: 'Événements',
          description: 'Expos, concours et rassemblements animaliers',
        ),
        _Section(
          icon: Icons.directions_walk_outlined,
          title: 'Promenade collective',
          description: 'Sorties groupées entre propriétaires près de chez vous',
        ),
      ],
    );
  }
}

class ProduitsPage extends StatelessWidget {
  const ProduitsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _ServiceSubPage(
      title: 'Produits',
      icon: Icons.shopping_bag_outlined,
      iconColor: const Color(0xFF8E24AA),
      headerColor: const Color(0xFF8E24AA),
      sections: const [
        _Section(
          icon: Icons.storefront_outlined,
          title: 'Boutiques en ligne & accessoires',
          description: 'Partenaires sélectionnés, jouets et accessoires pour animaux',
        ),
        _Section(
          icon: Icons.set_meal_outlined,
          title: 'Aliments & friandises',
          description: 'Croquettes, pâtées et snacks de qualité',
        ),
        _Section(
          icon: Icons.brush_outlined,
          title: 'Créateurs pour animaux',
          description: 'Créations artisanales, colliers, vêtements et objets personnalisés',
        ),
        _Section(
          icon: Icons.local_offer_outlined,
          title: 'Bons plans & promos',
          description: 'Offres exclusives pour la communauté',
        ),
      ],
    );
  }
}

class CommunautePage extends StatelessWidget {
  const CommunautePage({super.key});

  @override
  Widget build(BuildContext context) {
    return _ServiceSubPage(
      title: 'Communauté',
      icon: Icons.groups_outlined,
      iconColor: const Color(0xFF00ACC1),
      headerColor: const Color(0xFF00ACC1),
      sections: const [
        _Section(
          icon: Icons.forum_outlined,
          title: 'Forums',
          description: 'Discussions et entraide entre passionnés',
        ),
        _Section(
          icon: Icons.group_outlined,
          title: 'Groupes',
          description: 'Rejoignez des groupes par race ou passion',
        ),
        _Section(
          icon: Icons.pets,
          title: 'Balade canine',
          description: 'Organisez et rejoignez des balades groupées près de chez vous',
        ),
        _Section(
          icon: Icons.event_available_outlined,
          title: 'Événements locaux',
          description: 'Rencontres et activités près de chez vous',
        ),
        _Section(
          icon: Icons.volunteer_activism_outlined,
          title: 'Adoption & SPA',
          description: 'Animaux à adopter et refuges partenaires',
        ),
      ],
    );
  }
}

// ── Shared sub-page shell ────────────────────────────────────────────────────

class _Section {
  final IconData icon;
  final String title;
  final String description;

  const _Section({
    required this.icon,
    required this.title,
    required this.description,
  });
}

class _ServiceSubPage extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Color headerColor;
  final List<_Section> sections;

  const _ServiceSubPage({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.headerColor,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            backgroundColor: const Color(0xFF1E2025),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              titlePadding: const EdgeInsets.fromLTRB(56, 0, 20, 16),
              title: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                  color: Colors.white,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          headerColor.withOpacity(0.85),
                          const Color(0xFF1E2025),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: -20,
                    top: -10,
                    child: Icon(icon, size: 140,
                        color: Colors.white.withOpacity(0.07)),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SectionCard(
                    section: sections[index],
                    accentColor: iconColor,
                  ),
                ),
                childCount: sections.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final _Section section;
  final Color accentColor;

  const _SectionCard({required this.section, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(section.icon, color: accentColor, size: 22),
        ),
        title: Text(
          section.title,
          style: const TextStyle(
            fontFamily: 'Galey',
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          section.description,
          style: TextStyle(
            fontFamily: 'Galey',
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        trailing: Icon(Icons.arrow_forward_ios_rounded,
            size: 14, color: Colors.grey.shade400),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${section.title} — bientôt disponible',
                style: const TextStyle(fontFamily: 'Galey'),
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: accentColor,
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }
}
