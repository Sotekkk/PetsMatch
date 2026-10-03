import 'package:flutter/material.dart';
import 'package:PetsMatch/pages/eleveur/employes/employes_page.dart';

/// Équipe d'une association : une seule liste (employés + bénévoles, rôle
/// affiché sur chaque carte et choisi à l'ajout). L'ancien onglet
/// « Bénévoles » (BenevolesPage) faisait doublon et n'offrait aucune action
/// sur les bénévoles ajoutés depuis la recherche.
class EquipePage extends StatelessWidget {
  const EquipePage({super.key});

  @override
  Widget build(BuildContext context) => const EmployesPage(isAssociation: true);
}
