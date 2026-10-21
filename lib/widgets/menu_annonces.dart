// Menu « Annonces » unique des menus latéraux (tous profils) : trois
// entrées au plus — Mes annonces, Trouver un animal, Matériel & équipements. Miroir site :
// website/src/components/Header.tsx (sectionAnnonces).

import 'package:flutter/material.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/annonces/annonces_objets_feed_page.dart';
import 'package:PetsMatch/pages/eleveur/post/mes_annonces_page.dart';
import 'package:PetsMatch/pages/annonces/trouver_animal_page.dart';
import 'package:PetsMatch/widgets/menu_pro.dart';

/// Entrées du menu « Annonces ». La publication passe par « Mes annonces »
/// (bouton « Publier une annonce », choix du type dont le matériel) : pas
/// d'entrée « Publier une annonce » en double ici. [ouvrir] reprend la navigation du menu
/// appelant (fermeture du tiroir puis ouverture de la page). [extras] :
/// entrées propres à un profil, à la suite (aucune à ce jour).
List<Widget> entreesMenuAnnonces({
  required void Function(Widget page) ouvrir,
  List<Widget> extras = const [],
}) => [
  MenuProSubItem(
    label: 'Mes annonces',
    onTap: () => ouvrir(MesAnnoncesPage(isAssociation: User_Info.activeType == 'association')),
  ),
  // Recherche d'animaux, d'élevages et d'associations (onglets) avec
  // Liste / Fil / Carte : remplace Trouver un compagnon, Carte des
  // élevages / des associations, Annonces d'adoption, Fil adoption et Saillie.
  MenuProSubItem(label: 'Trouver un animal', onTap: () => ouvrir(const TrouverAnimalPage())),
  // Consultation du matériel des autres ; le sien se gère dans Mes annonces.
  MenuProSubItem(label: 'Matériel & équipements', onTap: () => ouvrir(const AnnoncesObjetsFeedPage())),
  ...extras,
];
