import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/particulier/first_page.dart';
import 'package:PetsMatch/pages/eleveur/first_page.dart';
import 'package:PetsMatch/pages/association/inscription_association_page.dart';
import 'package:PetsMatch/pages/pro/restauration/inscription_restauration_pro_page.dart';
import 'package:flutter/material.dart';

class InscriptionChoicePage extends StatelessWidget {
  const InscriptionChoicePage({super.key});

  static const _teal = Color(0xFF0C5C6C);
  static const _bg = Color(0xFFF8F8F6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Inscription',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Qui êtes-vous ?',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                  color: Color(0xFF1F2A2E))),
          const SizedBox(height: 6),
          Text('Choisissez le profil qui vous correspond.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade500)),
          const SizedBox(height: 28),
          _RoleCard(
            imagePath: 'assets/page/logo_particulier.png',
            title: 'Particulier',
            subtitle: 'Découvrez le compagnon idéal qui attend de partager une vie de joie et d\'amitié à vos côtés.',
            color: const Color(0xFFE8F5E9),
            onTap: () {
              User_Info.isElevage = false;
              User_Info.isPro = false;
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RegisterParticulierInformationPage()));
            },
          ),
          const SizedBox(height: 14),
          _RoleCard(
            imagePath: 'assets/page/logo_eleveur.png',
            title: 'Éleveur',
            subtitle: 'Éleveur de confiance pour des animaux équilibrés et en pleine santé.',
            color: const Color(0xFFE0F2F1),
            onTap: () {
              User_Info.isElevage = true;
              User_Info.isPro = false;
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RegisterEleveurInformationPage()));
            },
          ),
          const SizedBox(height: 14),
          _RoleCard(
            imagePath: 'assets/page/logo_professionnel.png',
            title: 'Professionnel',
            subtitle: 'Partagez votre savoir-faire avec la communauté PetsMatch.',
            color: const Color(0xFFF3E5F5),
            onTap: () {
              User_Info.isElevage = false;
              User_Info.isPro = true;
              User_Info.isAssociation = false;
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RegisterEleveurInformationPage()));
            },
          ),
          const SizedBox(height: 14),
          _RoleCard(
            imagePath: 'assets/page/logo_particulier.png',
            title: 'Association',
            subtitle: 'Refuge, SPA, association de protection animale accueillant des animaux.',
            color: const Color(0xFFE3F2FD),
            onTap: () {
              User_Info.isElevage = false;
              User_Info.isPro = false;
              User_Info.isAssociation = true;
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RegisterAssociationFirstInfoPage()));
            },
          ),
          const SizedBox(height: 14),
          _RoleCard(
            imagePath: 'assets/page/logo_professionnel.png',
            title: 'Hébergement / Restauration',
            subtitle: 'Hôtel, restaurant, café, gîte ou camping pet-friendly accueillant des animaux.',
            color: const Color(0xFFFFF8E1),
            onTap: () {
              User_Info.isElevage    = false;
              User_Info.isPro        = true;
              User_Info.isAssociation = false;
              User_Info.catPro       = 'restauration';
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const InscriptionRestaurationProPage()));
            },
          ),
        ]),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String imagePath;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RoleCard({
    required this.imagePath,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  static const _teal = Color(0xFF0C5C6C);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Image.asset(imagePath, fit: BoxFit.contain),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                              color: _teal)),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: TextStyle(
                              fontFamily: 'Galey',
                              fontSize: 12,
                              color: Colors.grey.shade500,
                              height: 1.4),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 14),
                child: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: _teal),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
