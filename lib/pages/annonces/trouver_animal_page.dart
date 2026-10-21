// « Trouver un animal » : destination unique de la recherche d'animaux,
// d'élevages et d'associations (onglets), avec ses modes d'affichage
// (Liste / Fil / Carte selon le contenu). Remplace les entrées séparées
// « Trouver un compagnon », « Carte des élevages », « Carte des
// associations », « Annonces d'adoption », « Fil adoption associations »
// et « Saillie » du menu. Les pages existantes (recherche, fil, carte,
// élevages, associations) en sont le contenu : mêmes données, filtres et règles.
// Miroir site : /annonces (+ /annonces/feed, /annonces/carte, /elevages,
// /associations) avec website/src/components/annonces/TrouverAnimalNav.tsx.

import 'package:flutter/material.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/association/associations_list_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_public_page.dart';
import 'package:PetsMatch/pages/eleveur_list_page.dart';

const _teal = Color(0xFF0C5C6C);
const _gris = Color(0xFF6F767B);
const _bordure = Color(0xFFE4E7EB);

/// Types d'annonce d'animal : 'tous' | 'compagnie' | 'adoption' | 'saillie'.
/// « Saillie » reste réservée aux éleveurs (règle existante du fil et de
/// « Trouver un compagnon ») ; « Tous » n'y mêle jamais de saillie pour eux.
List<(String, String)> typesAnnonceAutorises() => [
  ('tous', 'Tous'),
  ('compagnie', 'Compagnie'),
  ('adoption', 'Adoption'),
  if (User_Info.isElevage) ('saillie', 'Saillie'),
];

class TrouverAnimalPage extends StatefulWidget {
  /// 'animaux' | 'elevages' | 'associations'
  final String onglet;
  /// Type d'annonce de l'onglet Animaux (voir [typesAnnonceAutorises]).
  final String type;
  final String espece;
  const TrouverAnimalPage({super.key, this.onglet = 'animaux', this.type = 'tous', this.espece = 'tous'});

  @override
  State<TrouverAnimalPage> createState() => _TrouverAnimalPageState();
}

class _TrouverAnimalPageState extends State<TrouverAnimalPage> with SingleTickerProviderStateMixin {
  static const _onglets = ['animaux', 'elevages', 'associations'];
  late final TabController _tab = TabController(
      length: 3, vsync: this, initialIndex: _onglets.indexOf(widget.onglet).clamp(0, 2));

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = typesAnnonceAutorises().any((t) => t.$1 == widget.type) ? widget.type : 'tous';
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Trouver un animal',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500, fontSize: 14),
          tabs: const [Tab(text: 'Animaux'), Tab(text: 'Élevages'), Tab(text: 'Associations')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        // Les cartes gardent le geste horizontal.
        physics: const NeverScrollableScrollPhysics(),
        children: [
          AnnoncesPublicPage(embedded: true, typeAnnonce: type, initialEspece: widget.espece),
          const EleveurListPage(embedded: true),
          const AssociationsListPage(embedded: true),
        ],
      ),
    );
  }
}

/// Choix du mode d'affichage (Liste / Fil / Carte) — seuls les modes
/// existants pour le contenu affiché sont proposés.
class SelecteurModes extends StatelessWidget {
  /// (valeur, libellé, icône)
  final List<(String, String, IconData)> modes;
  final String actif;
  final ValueChanged<String> onChange;
  const SelecteurModes({super.key, required this.modes, required this.actif, required this.onChange});

  static const liste = ('liste', 'Liste', Icons.view_list_outlined);
  static const fil = ('fil', 'Fil', Icons.play_circle_outline_rounded);
  static const carte = ('carte', 'Carte', Icons.map_outlined);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _bordure),
      ),
      child: Row(children: [
        for (final m in modes)
          Expanded(child: GestureDetector(
            onTap: () => onChange(m.$1),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: actif == m.$1 ? _teal : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(m.$3, size: 17, color: actif == m.$1 ? Colors.white : _gris),
                const SizedBox(width: 6),
                Text(m.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w600,
                    color: actif == m.$1 ? Colors.white : _gris)),
              ]),
            ),
          )),
      ]),
    );
  }
}

/// Filtre « Type d'annonce » de l'onglet Animaux.
class ChipsTypeAnnonce extends StatelessWidget {
  final String actif;
  final ValueChanged<String> onChange;
  const ChipsTypeAnnonce({super.key, required this.actif, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final t in typesAnnonceAutorises())
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChange(t.$1),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: actif == t.$1 ? const Color(0xFFE8F4F6) : Colors.white,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: actif == t.$1 ? _teal : _bordure),
                ),
                child: Text(t.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 13.5,
                    fontWeight: actif == t.$1 ? FontWeight.w700 : FontWeight.w500,
                    color: actif == t.$1 ? _teal : _gris)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Bandeau blanc sous la barre de recherche : filtres de la vue + modes.
class BandeauTrouverAnimal extends StatelessWidget {
  final Widget? filtres;
  final Widget modes;
  const BandeauTrouverAnimal({super.key, this.filtres, required this.modes});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (filtres != null) ...[filtres!, const SizedBox(height: 10)],
      modes,
    ]),
  );
}
