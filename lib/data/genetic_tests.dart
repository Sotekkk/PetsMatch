import 'package:flutter/material.dart';

/// Tests génétiques / dépistages héréditaires par espèce — partagé entre les
/// fiches animal (éleveur via `animal_fiche.dart`, particulier via
/// `animal_fiche_particulier.dart`) et la vitrine reproducteurs.
/// Miroir web : `website/src/lib/genetics.ts`.
class GeneticTest {
  final String code;
  final String nom;
  final String categorie; // 'maladie' | 'adn' | 'robe' | 'aptitude'
  final String? races;
  const GeneticTest(this.code, this.nom, this.categorie, [this.races]);
}

const List<String> kGeneticTestCategories = ['maladie', 'adn', 'robe', 'aptitude', 'autre'];

const Map<String, String> kGeneticTestCategorieLabels = {
  'maladie': 'Maladie héréditaire',
  'adn': 'Profil ADN',
  'robe': 'Génétique de la robe',
  'aptitude': 'Aptitude / performance',
  'autre': 'Autre',
};

const Map<String, List<GeneticTest>> kGeneticTests = {
  'cheval': [
    GeneticTest('WFFS', 'Warmblood Fragile Foal Syndrome', 'maladie', 'Chevaux de sport'),
    GeneticTest('PSSM1', 'Myopathie à surcharge en polysaccharides type 1', 'maladie', 'Traits, Quarter, sport'),
    GeneticTest('PSSM2', 'Myopathie type 2 (P2/P3/P4/Px/K)', 'maladie'),
    GeneticTest('SCID', 'Immunodéficience combinée sévère', 'maladie', 'Arabe'),
    GeneticTest('CA', 'Ataxie cérébelleuse', 'maladie', 'Arabe'),
    GeneticTest('LFS', 'Lavender Foal Syndrome', 'maladie', 'Arabe'),
    GeneticTest('OAAM', 'Malformation occipito-atlanto-axiale', 'maladie', 'Arabe'),
    GeneticTest('HERDA', 'Asthénie cutanée régionale héréditaire', 'maladie', 'Quarter Horse'),
    GeneticTest('GBED', 'Déficit en enzyme de branchement du glycogène', 'maladie', 'Quarter Horse'),
    GeneticTest('HYPP', 'Paralysie périodique hyperkaliémique', 'maladie', 'Quarter Horse (Impressive)'),
    GeneticTest('MH', 'Hyperthermie maligne', 'maladie', 'Quarter Horse'),
    GeneticTest('MYHM', 'Myosite immuno-médiée (MYH1)', 'maladie', 'Quarter Horse'),
    GeneticTest('OLWS', 'Syndrome du poulain blanc létal (frame overo)', 'maladie', 'Paint'),
    GeneticTest('JEB', 'Épidermolyse bulleuse jonctionnelle', 'maladie', 'Traits (Breton, Comtois…)'),
    GeneticTest('FIS', 'Foal Immunodeficiency Syndrome', 'maladie', 'Fell / Dales'),
    GeneticTest('CSNB', 'Cécité nocturne stationnaire congénitale', 'maladie', 'Appaloosa (LP)'),
    GeneticTest('ADN', 'Profil ADN (typage / filiation)', 'adn'),
    GeneticTest('AGOUTI', 'Agouti (A)', 'robe'),
    GeneticTest('EXT', 'Extension (E)', 'robe'),
    GeneticTest('GREY', 'Grey (G)', 'robe'),
    GeneticTest('CREAM', 'Crème (Cr)', 'robe'),
    GeneticTest('TOBIANO', 'Tobiano (TO)', 'robe'),
    GeneticTest('LP', 'Léopard (LP)', 'robe'),
  ],
  'chien': [
    GeneticTest('HD', 'Dysplasie coxo-fémorale (hanches)', 'maladie'),
    GeneticTest('ED', 'Dysplasie du coude', 'maladie'),
    GeneticTest('PRA', 'Atrophie rétinienne progressive (APR)', 'maladie'),
    GeneticTest('MDR1', 'Sensibilité médicamenteuse (MDR1 / ABCB1)', 'maladie', 'Colley, Berger australien…'),
    GeneticTest('DM', 'Myélopathie dégénérative (SOD1)', 'maladie'),
    GeneticTest('VWD', 'Maladie de Von Willebrand', 'maladie'),
    GeneticTest('PATELLA', 'Luxation de la rotule', 'maladie'),
    GeneticTest('TARE_OCULAIRE', 'Dépistage des tares oculaires (annuel)', 'maladie'),
    GeneticTest('CARDIO', 'Dépistage cardiaque (échocardiographie)', 'maladie'),
    GeneticTest('DCM', 'Cardiomyopathie dilatée', 'maladie'),
    GeneticTest('CEA', 'Anomalie de l\'œil du Colley (CEA)', 'maladie'),
    GeneticTest('ADN', 'Profil ADN (identification / filiation)', 'adn'),
  ],
  'chat': [
    GeneticTest('PKD', 'Polykystose rénale (PKD1)', 'maladie', 'Persan, British…'),
    GeneticTest('HCM', 'Cardiomyopathie hypertrophique', 'maladie', 'Maine Coon, Ragdoll…'),
    GeneticTest('PK_DEF', 'Déficit en pyruvate kinase (PK-Def)', 'maladie'),
    GeneticTest('SMA', 'Amyotrophie spinale', 'maladie', 'Maine Coon'),
    GeneticTest('PRA', 'Atrophie rétinienne progressive (rdAc)', 'maladie', 'Abyssin, Somali…'),
    GeneticTest('GROUPE_SANGUIN', 'Groupe sanguin (A / B / AB)', 'aptitude'),
    GeneticTest('ADN', 'Profil ADN (identification / filiation)', 'adn'),
  ],
};

const Map<String, String> kResultatsGenetiques = {
  'clair': 'Indemne (N/N)',
  'porteur': 'Porteur (hétérozygote)',
  'homozygote': 'Homozygote atteint',
  'atteint': 'Atteint',
  'etabli': 'Établi',
  'indetermine': 'En attente / indéterminé',
};

/// Vrai si l'espèce a une section génétique dédiée.
bool especeHasGenetics(String? espece) =>
    espece == 'cheval' || espece == 'chien' || espece == 'chat';

String offspringWord(String? espece) => switch (espece) {
      'cheval' => 'poulains',
      'chien' => 'chiots',
      'chat' => 'chatons',
      _ => 'petits',
    };

Color resultatColor(String? r) => switch (r) {
      'clair' || 'etabli' => const Color(0xFF4d7a3c),
      'porteur' => const Color(0xFFB45309),
      'atteint' || 'homozygote' => const Color(0xFFC0392B),
      _ => const Color(0xFF6F767B),
    };

Color resultatBg(String? r) => switch (r) {
      'clair' || 'etabli' => const Color(0xFFEEF5EA),
      'porteur' => const Color(0xFFFFF4E5),
      'atteint' || 'homozygote' => const Color(0xFFFDECEC),
      _ => const Color(0xFFF1F1F1),
    };
