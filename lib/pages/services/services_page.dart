import 'package:flutter/material.dart';
import 'package:PetsMatch/pages/services/veterinaires_page.dart';

class ServicesPage extends StatelessWidget {
  const ServicesPage({super.key});

  static const _categories = [
    _ServiceCategory(
      icon: Icons.local_hospital_outlined,
      label: 'Vétérinaires',
      subtitle: 'Liste, avis & RDV',
      color: Color(0xFFE8F5E9),
      iconColor: const Color(0xFF6E9E57),
      page: VeterinairesPag(),
    ),
    _ServiceCategory(
      icon: Icons.volunteer_activism_outlined,
      label: 'Éducation & Garde',
      subtitle: 'Éducateurs, pet sitter & pension',
      color: Color(0xFFFFF3E0),
      iconColor: Color(0xFFEF6C00),
      page: EducationPage(),
    ),
    _ServiceCategory(
      icon: Icons.favorite_outline,
      label: 'Santé',
      subtitle: 'Nutrition & prévention',
      color: Color(0xFFFCE4EC),
      iconColor: Color(0xFFE91E63),
      page: SantePage(),
    ),
    _ServiceCategory(
      icon: Icons.park_outlined,
      label: 'Animal Friendly',
      subtitle: 'Parcs, restos & lieux acceptant les animaux',
      color: Color(0xFFE3F2FD),
      iconColor: Color(0xFF1E88E5),
      page: LieuxSympasPage(),
    ),
    _ServiceCategory(
      icon: Icons.shopping_bag_outlined,
      label: 'Produits',
      subtitle: 'Boutiques, accessoires & aliments',
      color: Color(0xFFF3E5F5),
      iconColor: Color(0xFF8E24AA),
      page: ProduitsPage(),
    ),
    _ServiceCategory(
      icon: Icons.groups_outlined,
      label: 'Communauté',
      subtitle: 'Forums, groupes & événements',
      color: Color(0xFFE0F7FA),
      iconColor: Color(0xFF00ACC1),
      page: CommunautePage(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 110,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF1F2A2E),
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              title: const Text(
                'Services',
                style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                  color: Colors.white,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1E2025),
                      Color(0xFF2C2F3A),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final cat = _categories[index];
                  return _CategoryCard(category: cat);
                },
                childCount: _categories.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.85,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceCategory {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final Color iconColor;
  final Widget page;

  const _ServiceCategory({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.iconColor,
    required this.page,
  });
}

class _CategoryCard extends StatelessWidget {
  final _ServiceCategory category;

  const _CategoryCard({required this.category});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => category.page),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: category.color,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  category.icon,
                  color: category.iconColor,
                  size: 28,
                ),
              ),
              const Spacer(),
              Text(
                category.label,
                style: const TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Color(0xFF1E2025),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                category.subtitle,
                style: TextStyle(
                  fontFamily: 'Galey',
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: category.iconColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
