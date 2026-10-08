import 'package:flutter/material.dart';
import 'package:PetsMatch/pages/services/service_list_page.dart';

class AnnuaireSubCategoryPage extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final List<AnnuaireSubItem> items;

  const AnnuaireSubCategoryPage({
    super.key,
    required this.title,
    required this.color,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(title,
            style: const TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
        // Plus de « Voir tous les professionnels » : doublon de la recherche,
        // où le menu Métier propose « Toute la santé », « Toute l'éducation »…
        // (miroir site).
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) => _buildItemCard(ctx, items[i]),
      ),
    );
  }

  Widget _buildItemCard(BuildContext context, AnnuaireSubItem item) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceListPage(
            categoryLabel: item.label,
            categoryColor: item.color ?? color,
            categoryIcon: item.icon,
            catProValues: item.catProValues,
            professionValues: item.professionValues,
            matchCreneauTypeGarde: item.matchCreneauTypeGarde,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: (item.color ?? color).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, color: item.color ?? color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.label,
                      style: const TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF1E2025))),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(item.subtitle!,
                        style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: 12,
                            color: Colors.grey.shade500)),
                  ],
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

class AnnuaireSubItem {
  final String label;
  final String? subtitle;
  final IconData icon;
  final Color? color;
  final List<String> catProValues;
  final List<String>? professionValues;
  // Repli : inclut aussi les profils dont la profession affichée ne matche
  // pas professionValues, mais qui ont au moins un créneau (creneaux_pro)
  // avec type_garde dans cette liste (ou nul = « les deux ») — ex. un
  // pet-sitter qui propose aussi des promenades apparaît dans « Promeneurs ».
  final List<String>? matchCreneauTypeGarde;

  const AnnuaireSubItem({
    required this.label,
    this.subtitle,
    required this.icon,
    this.color,
    required this.catProValues,
    this.professionValues,
    this.matchCreneauTypeGarde,
  });
}
