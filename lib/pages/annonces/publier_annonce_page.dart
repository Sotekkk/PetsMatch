// Point d'entrée unique « Publier une annonce » : l'utilisateur choisit le
// type, puis le formulaire existant correspondant s'ouvre (champs,
// validations, quotas et autorisations propres à chaque type inchangés).

import 'package:flutter/material.dart';
import 'package:PetsMatch/pages/association/post/create_annonce_asso_page.dart';
import 'package:PetsMatch/pages/eleveur/post/create_annonce_page.dart';
import 'package:PetsMatch/pages/particulier/create_annonce_cheval_page.dart';
import 'package:PetsMatch/pages/particulier/create_annonce_objet_page.dart';
import 'package:PetsMatch/utils/annonces_droits.dart';
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';

class PublierAnnoncePage extends StatelessWidget {
  const PublierAnnoncePage({super.key});

  @override
  Widget build(BuildContext context) {
    final animaux = typeAnimauxProfilActif();
    final Widget? formAnimal = switch (animaux) {
      'eleveur' => const CreateAnnoncePage(),
      'association' => const CreateAnnonceAssoPage(),
      'particulier' => const CreateAnnonceChevalPage(),
      _ => null,
    };
    final detailAnimal = switch (animaux) {
      'eleveur' => 'Compagnon, portée ou saillie, selon votre formule.',
      'association' => 'Annonce d\'adoption pour un animal de l\'association.',
      'particulier' => 'Annonce pour un cheval (vente, location, demi-pension…).',
      _ => 'Non disponible pour ce profil : les annonces d\'animaux sont réservées aux éleveurs, '
          'aux associations et aux particuliers (cheval).',
    };

    // Remplace l'écran de choix par le formulaire : le retour ramène à la page d'origine.
    void ouvrir(Widget page) =>
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      backgroundColor: kDashFond,
      appBar: AppBar(
        backgroundColor: kDashTeal, foregroundColor: Colors.white, surfaceTintColor: kDashTeal,
        title: const Text('Publier une annonce',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(dashMargeLaterale(context), 20, dashMargeLaterale(context), 32),
        children: [
          const Text('Que souhaitez-vous publier ?',
              style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Color(0xFF4B5563))),
          const SizedBox(height: 14),
          _Choix(
            icon: Icons.pets_outlined,
            titre: 'Animal',
            detail: detailAnimal,
            onTap: formAnimal == null ? null : () => ouvrir(formAnimal),
          ),
          const SizedBox(height: 12),
          _Choix(
            icon: Icons.inventory_2_outlined,
            titre: 'Matériel & équipements',
            detail: 'Paniers, grilles de chenil, parcs, caisses de transport, équipements de mise bas… Jamais d\'animal.',
            onTap: () => ouvrir(const CreateAnnonceObjetPage()),
          ),
        ],
      ),
    );
  }
}

class _Choix extends StatelessWidget {
  final IconData icon;
  final String titre;
  final String detail;
  final VoidCallback? onTap;
  const _Choix({required this.icon, required this.titre, required this.detail, this.onTap});

  @override
  Widget build(BuildContext context) {
    final actif = onTap != null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kDashBorder), boxShadow: kDashOmbre),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: actif ? const Color(0xFFE8F4F6) : Colors.grey.shade100, shape: BoxShape.circle),
              child: Icon(icon, size: 22, color: actif ? kDashTeal : Colors.grey.shade400),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titre, style: TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w700,
                  color: actif ? kDashInk : Colors.grey.shade500)),
              const SizedBox(height: 3),
              Text(detail, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                  color: actif ? const Color(0xFF4B5563) : Colors.grey.shade500, height: 1.35)),
            ])),
            if (actif) ...[
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: kDashMuted),
            ],
          ]),
        ),
      ),
    );
  }
}
