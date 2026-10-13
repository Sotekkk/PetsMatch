// especes_elevees est stocké sous deux formes selon le parcours de création :
//   • inscription / édition du profil élevage : [{espece: 'chien', races: […]}]
//   • « Ajouter un profil » (avant correctif)  : ['Chien', 'Chat', 'NAC']
// Les écrans comparent aux valeurs de kSpeciesData ('chien', 'nac'…) : une
// liste en libellés ne correspondait à rien → plus aucune espèce proposée à la
// création d'annonce, donc aucune race. On normalise à la lecture comme à
// l'écriture. Miroir site : website/src/lib/especes-elevees.ts.

const _alias = {
  'chien': 'chien', 'chiens': 'chien',
  'chat': 'chat', 'chats': 'chat',
  'cheval': 'cheval', 'chevaux': 'cheval', 'equide': 'cheval', 'équidé': 'cheval',
  'lapin': 'lapin', 'lapins': 'lapin',
  'oiseau': 'oiseau', 'oiseaux': 'oiseau',
  'ovin': 'ovin', 'caprin': 'caprin', 'porcin': 'porcin',
  'nac': 'nac', 'rongeur': 'nac', 'rongeurs': 'nac', 'reptile': 'nac', 'reptiles': 'nac',
  'autre': 'autre',
};

/// Valeur canonique ('chien', 'nac'…) d'un libellé ou d'une valeur, ou null.
String? especeCanonique(String? brut) {
  final k = (brut ?? '').trim().toLowerCase();
  return k.isEmpty ? null : _alias[k];
}

/// Espèces élevées, en valeurs canoniques, quelle que soit la forme stockée.
List<String> especesEleveesDepuis(dynamic raw) {
  if (raw is! List) return [];
  final out = <String>[];
  for (final e in raw) {
    final v = especeCanonique(e is Map ? e['espece']?.toString() : e?.toString());
    if (v != null && !out.contains(v)) out.add(v);
  }
  return out;
}

/// Forme à enregistrer (celle de l'inscription) : [{espece, races}].
List<Map<String, dynamic>> especesEleveesPourBdd(Iterable<String> especes) {
  final vus = <String>{};
  return [
    for (final e in especes)
      if (especeCanonique(e) case final v? when vus.add(v)) {'espece': v, 'races': <String>[]},
  ];
}
