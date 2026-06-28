import 'package:flutter/material.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/widgets/app_nav_drawer.dart';
import 'package:PetsMatch/pages/services/service_list_page.dart';
import 'package:PetsMatch/pages/animal_friendly/friendly_map_page.dart';
import 'package:PetsMatch/pages/evenements/evenements_page.dart';
import 'package:PetsMatch/pages/promenades/promenades_page.dart';
import 'package:PetsMatch/pages/communaute/forum_page.dart';
import 'package:PetsMatch/pages/communaute/groupes_page.dart';
import 'package:PetsMatch/pages/lieux/lieux_pet_friendly_page.dart';
import 'package:PetsMatch/pages/petfriends/petfriends_page.dart';
import 'package:PetsMatch/pages/nature/natural_places_page.dart';

class VeterinairesPag extends StatelessWidget {
  const VeterinairesPag({super.key});

  @override
  Widget build(BuildContext context) {
    return _ServiceSubPage(
      title: 'Vétérinaires',
      iconColor: const Color(0xFF6E9E57),
      headerColor: const Color(0xFF6E9E57),
      sections: [
        _Section(
          icon: Icons.list_alt_outlined,
          title: 'Annuaire',
          description: 'Trouvez un vétérinaire près de chez vous',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Vétérinaires',
            categoryColor: Color(0xFF6E9E57),
            categoryIcon: Icons.local_hospital_outlined,
            catProValues: ['sante', 'veterinaire'],
          ))),
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
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Urgences vétérinaires',
            categoryColor: Color(0xFFE53935),
            categoryIcon: Icons.emergency_outlined,
            catProValues: ['sante', 'veterinaire'],
          ))),
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
      iconColor: const Color(0xFFEF6C00),
      headerColor: const Color(0xFFEF6C00),
      sections: [
        _Section(
          icon: Icons.psychology_outlined,
          title: 'Éducateurs / Comportementalistes',
          description: 'Professionnels certifiés en éducation et comportement animal',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Éducateurs',
            categoryColor: Color(0xFFEF6C00),
            categoryIcon: Icons.psychology_outlined,
            catProValues: ['education', 'garde'],
            professionValues: ['Éducateur comportementaliste', 'Maître-chien', 'Dresseur'],
          ))),
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
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Pet sitter & Promeneurs',
            categoryColor: Color(0xFFEF6C00),
            categoryIcon: Icons.directions_walk_outlined,
            catProValues: ['garde'],
            professionValues: ['Pet sitter', 'Promeneur de chiens'],
          ))),
        ),
        _Section(
          icon: Icons.house_outlined,
          title: 'Pension pour animaux',
          description: 'Hébergement et garderie lors de vos absences',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Pensions',
            categoryColor: Color(0xFFEF6C00),
            categoryIcon: Icons.house_outlined,
            catProValues: ['pension', 'garde'],
            professionValues: ['Pension', 'Pension pour animaux'],
          ))),
        ),
        _Section(
          icon: Icons.camera_alt_outlined,
          title: 'Photographes animaliers',
          description: 'Portraits, reportages et séances photo de vos animaux',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Photographes',
            categoryColor: Color(0xFFEF6C00),
            categoryIcon: Icons.camera_alt_outlined,
            catProValues: ['photographe'],
          ))),
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
      iconColor: const Color(0xFFE91E63),
      headerColor: const Color(0xFFE91E63),
      sections: [
        _Section(
          icon: Icons.self_improvement_outlined,
          title: 'Ostéopathes',
          description: 'Ostéopathie animale — chiens, chats, chevaux et NAC',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Ostéopathes',
            categoryColor: Color(0xFFE91E63),
            categoryIcon: Icons.self_improvement_outlined,
            catProValues: ['sante'],
            professionValues: ['Ostéopathe animalier'],
          ))),
        ),
        _Section(
          icon: Icons.accessibility_new_outlined,
          title: 'Kinésithérapeutes',
          description: 'Rééducation, mobilité et récupération post-opératoire',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Kinésithérapeutes',
            categoryColor: Color(0xFFE91E63),
            categoryIcon: Icons.accessibility_new_outlined,
            catProValues: ['sante'],
            professionValues: ['Kinésithérapeute animalier'],
          ))),
        ),
        _Section(
          icon: Icons.eco_outlined,
          title: 'Naturopathes',
          description: 'Médecine naturelle, phytothérapie et aromathérapie',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Naturopathes',
            categoryColor: Color(0xFFE91E63),
            categoryIcon: Icons.eco_outlined,
            catProValues: ['sante'],
            professionValues: ['Naturopathe animalier'],
          ))),
        ),
        _Section(
          icon: Icons.spa_outlined,
          title: 'Acupuncteurs',
          description: 'Acupuncture et médecines alternatives pour animaux',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Acupuncteurs',
            categoryColor: Color(0xFFE91E63),
            categoryIcon: Icons.spa_outlined,
            catProValues: ['sante'],
            professionValues: ['Acupuncteur animalier'],
          ))),
        ),
        _Section(
          icon: Icons.psychology_alt_outlined,
          title: 'Homéopathes',
          description: 'Traitements homéopathiques adaptés à votre animal',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Homéopathes',
            categoryColor: Color(0xFFE91E63),
            categoryIcon: Icons.psychology_alt_outlined,
            catProValues: ['sante'],
            professionValues: ['Homéopathe animalier'],
          ))),
        ),
        _Section(
          icon: Icons.biotech_outlined,
          title: 'Autres thérapeutes',
          description: 'Chiropracteurs, magnétiseurs, énergéticiens animaux',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Autres thérapeutes',
            categoryColor: Color(0xFFE91E63),
            categoryIcon: Icons.biotech_outlined,
            catProValues: ['sante'],
          ))),
        ),
      ],
    );
  }
}

class SortiesPage extends StatelessWidget {
  const SortiesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _ServiceSubPage(
      title: 'Sorties & Voyages',
      iconColor: const Color(0xFF1E88E5),
      headerColor: const Color(0xFF1E88E5),
      sections: [
        _Section(
          icon: Icons.grass_outlined,
          title: 'Parcs & espaces verts',
          description: 'Aires de jeux et balades avec votre animal',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(
            builder: (_) => const FriendlyMapPage(filterCategory: 'Randonnée / Parc'))),
        ),
        _Section(
          icon: Icons.store_outlined,
          title: 'Cafés, restaurants & hébergements',
          description: 'Tous les établissements pet-friendly en France',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(
            builder: (_) => const LieuxPetFriendlyPage())),
        ),
        _Section(
          icon: Icons.event_outlined,
          title: 'Événements',
          description: 'Expos, concours et rassemblements animaliers',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const EvenementsPage())),
        ),
        _Section(
          icon: Icons.directions_walk_outlined,
          title: 'Promenade collective',
          description: 'Sorties groupées entre propriétaires près de chez vous',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const PromenadePage())),
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
      title: 'Marketplace',
      iconColor: const Color(0xFF8E24AA),
      headerColor: const Color(0xFF8E24AA),
      sections: [
        _Section(
          icon: Icons.storefront_outlined,
          title: 'Boutiques en ligne & accessoires',
          description: 'Partenaires sélectionnés, jouets et accessoires pour animaux',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Boutiques',
            categoryColor: Color(0xFF8E24AA),
            categoryIcon: Icons.storefront_outlined,
            catProValues: ['referencement'],
            professionValues: ['Boutique en ligne'],
          ))),
        ),
        _Section(
          icon: Icons.set_meal_outlined,
          title: 'Aliments & friandises',
          description: 'Croquettes, pâtées et snacks de qualité',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Fournisseurs alimentaires',
            categoryColor: Color(0xFF8E24AA),
            categoryIcon: Icons.set_meal_outlined,
            catProValues: ['referencement'],
            professionValues: ["Fournisseur d'aliments"],
          ))),
        ),
        _Section(
          icon: Icons.brush_outlined,
          title: 'Créateurs pour animaux',
          description: 'Créations artisanales, colliers, vêtements et objets personnalisés',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Créateurs',
            categoryColor: Color(0xFF8E24AA),
            categoryIcon: Icons.brush_outlined,
            catProValues: ['referencement'],
            professionValues: ['Créateur pour animaux'],
          ))),
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

class CommunautePage extends StatefulWidget {
  const CommunautePage({super.key});
  @override
  State<CommunautePage> createState() => _CommunautePageState();
}

class _CommunautePageState extends State<CommunautePage> {
  @override
  void initState() {
    super.initState();
    User_Info.profileNotifier.addListener(_onProfileChange);
  }

  @override
  void dispose() {
    User_Info.profileNotifier.removeListener(_onProfileChange);
    super.dispose();
  }

  void _onProfileChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isParticulier = User_Info.activeType == 'particulier';
    return _ServiceSubPage(
      title: 'Communauté',
      iconColor: const Color(0xFF00ACC1),
      headerColor: const Color(0xFF00ACC1),
      sections: [
        if (isParticulier)
          _Section(
            icon: Icons.people_alt_outlined,
            title: 'PetsFriends',
            description: 'Connectez-vous avec d\'autres passionnés d\'animaux',
            onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const PetFriendsPage())),
          ),
        _Section(
          icon: Icons.forum_outlined,
          title: 'Forums',
          description: 'Discussions et entraide entre passionnés',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ForumPage())),
        ),
        _Section(
          icon: Icons.group_outlined,
          title: 'Groupes',
          description: 'Rejoignez des groupes par race ou passion',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const GroupesPage())),
        ),
        _Section(
          icon: Icons.pets,
          title: 'Balade canine',
          description: 'Organisez et rejoignez des balades groupées près de chez vous',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const PromenadePage())),
        ),
        _Section(
          icon: Icons.event_available_outlined,
          title: 'Événements locaux',
          description: 'Rencontres et activités près de chez vous',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const EvenementsPage())),
        ),
        _Section(
          icon: Icons.forest_outlined,
          title: 'Lieux Naturels',
          description: 'Forêts, plages, parcs & lacs pet-friendly près de chez vous',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const NaturalPlacesPage())),
        ),
      ],
    );
  }
}

class PoleSantePage extends StatelessWidget {
  const PoleSantePage({super.key});

  @override
  Widget build(BuildContext context) {
    return _ServiceSubPage(
      title: 'Pôle Santé',
      iconColor: const Color(0xFF6E9E57),
      headerColor: const Color(0xFF6E9E57),
      sections: [
        _Section(
          icon: Icons.local_hospital_outlined,
          title: 'Vétérinaires',
          description: 'Trouvez un vétérinaire près de chez vous',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Vétérinaires',
            categoryColor: Color(0xFF6E9E57),
            categoryIcon: Icons.local_hospital_outlined,
            catProValues: ['sante', 'veterinaire'],
          ))),
        ),
        _Section(
          icon: Icons.emergency_outlined,
          title: 'Urgences vétérinaires',
          description: 'Vétérinaires disponibles 24h/24',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Urgences vétérinaires',
            categoryColor: Color(0xFFE53935),
            categoryIcon: Icons.emergency_outlined,
            catProValues: ['sante', 'veterinaire'],
          ))),
        ),
        _Section(
          icon: Icons.self_improvement_outlined,
          title: 'Ostéopathes',
          description: 'Ostéopathie animale — chiens, chats, chevaux et NAC',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Ostéopathes',
            categoryColor: Color(0xFF6E9E57),
            categoryIcon: Icons.self_improvement_outlined,
            catProValues: ['sante'],
            professionValues: ['Ostéopathe animalier'],
          ))),
        ),
        _Section(
          icon: Icons.accessibility_new_outlined,
          title: 'Kinésithérapeutes',
          description: 'Rééducation, mobilité et récupération post-opératoire',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Kinésithérapeutes',
            categoryColor: Color(0xFF6E9E57),
            categoryIcon: Icons.accessibility_new_outlined,
            catProValues: ['sante'],
            professionValues: ['Kinésithérapeute animalier'],
          ))),
        ),
        _Section(
          icon: Icons.eco_outlined,
          title: 'Naturopathes',
          description: 'Médecine naturelle, phytothérapie et aromathérapie',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Naturopathes',
            categoryColor: Color(0xFF6E9E57),
            categoryIcon: Icons.eco_outlined,
            catProValues: ['sante'],
            professionValues: ['Naturopathe animalier'],
          ))),
        ),
        _Section(
          icon: Icons.spa_outlined,
          title: 'Médecines alternatives',
          description: 'Acupuncture, homéopathie, chiropractie animale',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Médecines alternatives',
            categoryColor: Color(0xFF6E9E57),
            categoryIcon: Icons.spa_outlined,
            catProValues: ['sante'],
          ))),
        ),
        _Section(
          icon: Icons.health_and_safety_outlined,
          title: 'Assurances animaux',
          description: 'Comparez les offres d\'assurance pour votre animal',
        ),
        _Section(
          icon: Icons.handyman_outlined,
          title: 'Maréchaux-ferrants',
          description: 'Parage, ferrure et soins des sabots pour chevaux',
          onTap: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const ServiceListPage(
            categoryLabel: 'Maréchaux-ferrants',
            categoryColor: Color(0xFF6E9E57),
            categoryIcon: Icons.handyman_outlined,
            catProValues: ['marechal_ferrant', 'sante'],
            professionValues: ['Maréchal-ferrant traditionnel', 'Parage naturel'],
          ))),
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
  final void Function(BuildContext ctx)? onTap;

  const _Section({
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
  });
}

class _ServiceSubPage extends StatelessWidget {
  final String title;
  final Color iconColor;
  final Color headerColor;
  final List<_Section> sections;

  const _ServiceSubPage({
    required this.title,
    required this.iconColor,
    required this.headerColor,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      endDrawer: const AppNavDrawer(),
      appBar: AppBar(
        backgroundColor: headerColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Galey',
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        actions: [
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu_rounded),
              tooltip: 'Menu',
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
        itemCount: sections.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _SectionCard(
          section: sections[index],
          accentColor: iconColor,
        ),
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
            color: Colors.black.withValues(alpha: 0.05),
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
            color: accentColor.withValues(alpha: 0.1),
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
        trailing: Icon(
          section.onTap != null
              ? Icons.arrow_forward_ios_rounded
              : Icons.lock_clock_outlined,
          size: 14,
          color: section.onTap != null ? accentColor : Colors.grey.shade300,
        ),
        onTap: section.onTap != null
            ? () => section.onTap!(context)
            : () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${section.title} — bientôt disponible',
                      style: const TextStyle(fontFamily: 'Galey'),
                    ),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: accentColor,
                    duration: const Duration(seconds: 2),
                  ),
                ),
      ),
    );
  }
}
