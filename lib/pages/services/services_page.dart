import 'package:flutter/material.dart';
import 'package:PetsMatch/pages/services/veterinaires_page.dart';

class ServicesPage extends StatelessWidget {
  const ServicesPage({super.key});

  static const _categories = [
    _ServiceCategory(
      icon: Icons.medical_services_outlined,
      label: 'Pôle Santé',
      subtitle: 'Vétérinaires, ostéopathes & thérapeutes',
      color: Color(0xFFE8F5E9),
      iconColor: Color(0xFF6E9E57),
      page: PoleSantePage(),
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
      icon: Icons.explore_outlined,
      label: 'Sorties & Voyages',
      subtitle: 'Parcs, restos & hébergements pet-friendly',
      color: Color(0xFFE3F2FD),
      iconColor: Color(0xFF1E88E5),
      page: SortiesPage(),
    ),
    _ServiceCategory(
      icon: Icons.shopping_bag_outlined,
      label: 'Marketplace',
      subtitle: 'Petfood, accessoires & créateurs',
      color: Color(0xFFF3E5F5),
      iconColor: Color(0xFF8E24AA),
      page: ProduitsPage(),
    ),
    _ServiceCategory(
      icon: Icons.groups_outlined,
      label: 'Communauté',
      subtitle: 'Forums, groupes & adoption',
      color: Color(0xFFE0F7FA),
      iconColor: Color(0xFF00ACC1),
      page: CommunautePage(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        title: const Text('Services',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFF0C5C6C),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
        itemCount: _categories.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.85,
        ),
        itemBuilder: (context, index) {
          final cat = _categories[index];
          return _CategoryCard(category: cat);
        },
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
              color: Colors.black.withValues(alpha: 0.06),
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
                  fontSize: 14,
                  color: Color(0xFF1E2025),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                category.subtitle,
                style: TextStyle(
                  fontFamily: 'Galey',
                  fontSize: 11,
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
