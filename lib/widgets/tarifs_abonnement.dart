import 'package:flutter/material.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/abonnement_page.dart';
import 'package:PetsMatch/pages/pro/education_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/garde_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/pension_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/photographe_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/sante_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/vet_abonnement_page.dart';

/// « Tarifs et abonnement » (menu « Mon Profil ») : offres et abonnement du
/// profil ACTIF uniquement. Miroir site : `/tarifs?metier=…`
/// depuis « Mon Profil » (components/Header.tsx). Aucune entrée pour une
/// association (gratuite) ni un particulier.
/// Restauration : formules de l'abonnement éleveur (comme l'ancienne entrée
/// « Mon abonnement »). Autres métiers sans offre (taxi…) : pas d'entrée.
const _metiersAvecOffre = {
  'pension', 'garde', 'education', 'photographe', 'toilettage',
  'veterinaire', 'sante', 'marechal_ferrant', 'restauration',
};

bool aTarifsAbonnement() =>
    User_Info.activeType != 'association' && User_Info.activeType != 'particulier'
    && (User_Info.isPro ? _metiersAvecOffre.contains(User_Info.catPro) : User_Info.isElevage);

Widget pageTarifsAbonnement() => switch (User_Info.isPro ? User_Info.catPro : '') {
  'pension' => const PensionAbonnementPage(),
  'garde' => const GardeAbonnementPage(),
  'education' => const EducationAbonnementPage(),
  'photographe' => const PhotographeAbonnementPage(),
  'toilettage' => const ToilettageAbonnementPage(),
  'veterinaire' => const VetAbonnementPage(),
  'sante' => const SanteAbonnementPage(profilType: 'sante'),
  'marechal_ferrant' => const SanteAbonnementPage(profilType: 'marechal_ferrant'),
  _ => const AbonnementPage(),
};
