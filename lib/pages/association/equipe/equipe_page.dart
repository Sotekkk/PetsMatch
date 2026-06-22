import 'package:flutter/material.dart';
import 'package:PetsMatch/pages/eleveur/employes/employes_page.dart';
import 'package:PetsMatch/pages/association/benevoles/benevoles_page.dart';

class EquipePage extends StatelessWidget {
  const EquipePage({super.key});

  static const _teal = Color(0xFF0C5C6C);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F8F6),
        appBar: AppBar(
          backgroundColor: _teal,
          foregroundColor: Colors.white,
          title: const Text('Équipe',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          bottom: const TabBar(
            indicatorColor: Color(0xFF6E9E57),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            labelStyle: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14),
            unselectedLabelStyle: TextStyle(fontFamily: 'Galey', fontSize: 14),
            tabs: [
              Tab(icon: Icon(Icons.badge_outlined, size: 20), text: 'Employés'),
              Tab(icon: Icon(Icons.volunteer_activism_outlined, size: 20), text: 'Bénévoles'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            EmployesPage(isAssociation: true),
            BenevolesPage(),
          ],
        ),
      ),
    );
  }
}
