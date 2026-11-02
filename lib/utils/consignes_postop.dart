// Consignes postopératoires pour le propriétaire (migration_consignes_postop.sql) :
// document distinct du compte rendu opératoire, en sections de texte simple
// (titres « ## », listes « - », gras « **…** »). Les modèles fournis ne
// contiennent QUE la structure et des indications de rédaction : aucune
// consigne médicale n'est écrite d'office ; la clinique rédige son texte et
// l'enregistre comme modèle (consignes_modeles). Le préremplissage ne reprend
// que des données déjà saisies. Miroir site : website/src/lib/consignes-postop.ts.

class SectionConsigne {
  String titre, texte;
  final String aide;
  SectionConsigne({required this.titre, this.texte = '', this.aide = ''});
  SectionConsigne copie() => SectionConsigne(titre: titre, texte: texte, aide: aide);
  Map<String, dynamic> toJson() => {'titre': titre.trim(), 'texte': texte.trim(), if (aide.isNotEmpty) 'aide': aide};
  factory SectionConsigne.fromJson(Map j) =>
      SectionConsigne(titre: (j['titre'] ?? '').toString(), texte: (j['texte'] ?? '').toString(), aide: (j['aide'] ?? '').toString());
}

List<SectionConsigne> sectionsConsignes() => [
  SectionConsigne(titre: 'Intervention réalisée', aide: 'Bref résumé, en termes simples, de ce qui a été fait.'),
  SectionConsigne(titre: 'Repos et activité', aide: 'Durée du repos, sorties, escaliers, jeux, restrictions.'),
  SectionConsigne(titre: 'Alimentation et hydratation', aide: 'Quand et comment reprendre l’alimentation et la boisson.'),
  SectionConsigne(titre: 'Surveillance', aide: 'Ce que le propriétaire doit observer les premiers jours.'),
  SectionConsigne(titre: 'Plaie et cicatrisation', aide: 'Protection de la plaie, collerette, pansement, soins, bain.'),
  SectionConsigne(titre: 'Traitements', aide: 'Résumé des traitements ; le détail figure sur l’ordonnance.'),
  SectionConsigne(titre: 'Signes nécessitant de contacter la clinique', aide: 'Signes d’alerte définis par le vétérinaire.'),
  SectionConsigne(titre: 'Prochains contrôles', aide: 'Dates ou délais des contrôles, retrait des fils.'),
  SectionConsigne(titre: 'Coordonnées de la clinique', aide: 'Téléphone, horaires, urgences.'),
];

/// Modèles de base : structure seule, à compléter par la clinique.
List<({String? id, String nom, List<SectionConsigne> sections})> modelesBaseConsignes() => [
  for (final n in ['Stérilisation', 'Castration', 'Chirurgie abdominale', 'Chirurgie orthopédique', 'Intervention dentaire', 'Autre intervention'])
    (id: null, nom: '$n (structure vide)', sections: sectionsConsignes()),
];

/// Sections de départ complétées par les données déjà enregistrées (jamais de consigne inventée).
List<SectionConsigne> prerempliConsignes(List<SectionConsigne> base, {String intervention = '', String traitements = '',
    String controles = '', String prochainRdv = '', List<String> cliniqueCoord = const []}) {
  final out = [for (final s in base) s.copie()];
  void remplir(String titre, String texte) {
    for (final s in out) {
      if (s.titre == titre && s.texte.trim().isEmpty && texte.trim().isNotEmpty) s.texte = texte.trim();
    }
  }
  remplir('Intervention réalisée', intervention);
  remplir('Traitements', traitements.trim().isEmpty ? '' : '${traitements.trim()}\n\nLe détail (doses, durée) figure sur l’ordonnance.');
  remplir('Prochains contrôles', [controles, if (prochainRdv.trim().isNotEmpty) 'Prochain rendez-vous : $prochainRdv']
      .where((x) => x.trim().isNotEmpty).join('\n'));
  remplir('Coordonnées de la clinique', cliniqueCoord.join('\n'));
  return out;
}

({List<String> bloquants, List<String> avertissements}) controlerConsignes(List<SectionConsigne> sections) {
  final bloquants = <String>[], avertissements = <String>[];
  if (!sections.any((s) => s.texte.trim().isNotEmpty)) bloquants.add('Au moins une section rédigée');
  if (sections.any((s) => s.titre.trim().isEmpty && s.texte.trim().isNotEmpty)) bloquants.add('Une section rédigée n’a pas de titre');
  bool vide(String t) => !sections.any((s) => s.titre == t && s.texte.trim().isNotEmpty);
  if (vide('Signes nécessitant de contacter la clinique')) avertissements.add('Signes d’alerte non renseignés');
  if (vide('Coordonnées de la clinique')) avertissements.add('Coordonnées de la clinique non renseignées');
  if (sections.any((s) => s.texte.trim().isEmpty)) avertissements.add('Les sections vides ne figureront pas sur le document');
  return (bloquants: bloquants, avertissements: avertissements);
}

/// Texte simple → blocs (titre « ## », puce « - », paragraphe) avec segments gras.
typedef SegmentConsigne = ({String texte, bool gras});
typedef BlocConsigne = ({String type, List<SegmentConsigne> segments});

List<SegmentConsigne> segmentsGras(String ligne) {
  final parts = ligne.split('**');
  return [for (var i = 0; i < parts.length; i++) if (parts[i].isNotEmpty) (texte: parts[i], gras: i.isOdd)];
}

List<BlocConsigne> blocsConsigne(String texte) => [
  for (final brut in texte.split('\n'))
    if (brut.trim().isNotEmpty)
      brut.trim().startsWith('## ')
          ? (type: 'titre', segments: segmentsGras(brut.trim().substring(3)))
          : RegExp(r'^[-•*]\s+').hasMatch(brut.trim())
              ? (type: 'puce', segments: segmentsGras(brut.trim().replaceFirst(RegExp(r'^[-•*]\s+'), '')))
              : (type: 'paragraphe', segments: segmentsGras(brut.trim())),
];
