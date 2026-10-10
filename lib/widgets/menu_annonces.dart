// Menu « Annonces » unique des menus latéraux (tous profils) : animaux et
// matériel & équipements regroupés. Remplace l'ancien découpage
// « Annonces » / « Petites annonces (matériel) ». Miroir site :
// website/src/components/Header.tsx (sectionAnnonces).

import 'package:flutter/material.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/annonces/annonces_objets_feed_page.dart';
import 'package:PetsMatch/pages/annonces/publier_annonce_page.dart';
import 'package:PetsMatch/pages/eleveur/post/mes_annonces_page.dart';
import 'package:PetsMatch/pages/eleveur/post/trouver_compagnon_page.dart';
import 'package:PetsMatch/pages/eleveur_list_page.dart';
import 'package:PetsMatch/widgets/menu_pro.dart';

/// Entrées du menu « Annonces ». [ouvrir] reprend la navigation du menu
/// appelant (fermeture du tiroir puis ouverture de la page). [extras] :
/// entrées propres au profil conservées à la suite (ex. Adoptions).
List<Widget> entreesMenuAnnonces({
  required void Function(Widget page) ouvrir,
  List<Widget> extras = const [],
}) => [
  MenuProSubItem(
    label: 'Mes annonces',
    onTap: () => ouvrir(MesAnnoncesPage(isAssociation: User_Info.activeType == 'association')),
  ),
  MenuProSubItem(label: 'Publier une annonce', onTap: () => ouvrir(const PublierAnnoncePage())),
  MenuProSubItem(label: 'Trouver un compagnon', onTap: () => ouvrir(const TrouverCompagnonPage())),
  MenuProSubItem(label: 'Matériel & équipements', onTap: () => ouvrir(const AnnoncesObjetsFeedPage())),
  MenuProSubItem(label: 'Carte des élevages', onTap: () => ouvrir(const EleveurListPage())),
  ...extras,
];
