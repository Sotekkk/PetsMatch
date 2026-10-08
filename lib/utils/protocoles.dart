// Protocoles (plan_templates) — périmètre, libellés et calcul des dates.
// Miroir site : website/src/lib/protocoles.ts — garder les deux synchronisés.

/// 'animal' | 'portee' | 'cheptel' | 'categorie' | 'locaux'
const kPerimetres = <(String, String, String)>[
  ('animal',    'Un ou plusieurs animaux', 'Choisis maintenant ou au moment d’appliquer'),
  ('portee',    'Une portée',              'La portée est choisie au moment d’appliquer'),
  ('cheptel',   'Tout le cheptel',         'Tous les animaux (de l’espèce choisie)'),
  ('categorie', 'Une catégorie d’animaux', 'Mâles, femelles, femelles gestantes, jeunes…'),
  ('locaux',    'Locaux / matériel',       'Aucun animal : une tâche par occurrence'),
];

/// Catégories d'animaux (valeurs historiques de cible_type).
const kCategoriesProtocole = <(String, String)>[
  ('males',       'Mâles'),
  ('femelles',    'Femelles'),
  ('gestantes',   'Femelles gestantes'),
  ('allaitantes', 'Femelles allaitantes'),
  ('bebes',       'Bébés / jeunes'),
];

const _typesLocaux = ['nettoyage', 'materiel'];

/// Périmètre effectif. Les anciens protocoles de nettoyage / matériel étaient
/// enregistrés en « cheptel » (le formulaire l'imposait) alors qu'ils portent
/// sur les locaux : ils sont lus comme « locaux » (aucun animal).
String perimetreDe(Map<String, dynamic> t, {String? profilSource}) {
  final c = (t['cible_type'] ?? 'individuel').toString();
  if (c == 'locaux') return 'locaux';
  if (c == 'portee') return 'portee';
  if (c == 'individuel') return 'animal';
  if (kCategoriesProtocole.any((k) => k.$1 == c)) return 'categorie';
  if (c == 'cheptel' && _typesLocaux.contains(t['type']) && profilSource != 'garde') return 'locaux';
  return 'cheptel';
}

String cibleTypePour(String perimetre, String categorie) =>
    perimetre == 'animal' ? 'individuel' : perimetre == 'categorie' ? categorie : perimetre;

const _especesPluriel = {
  'chien': 'chiens', 'chat': 'chats', 'cheval': 'chevaux', 'lapin': 'lapins', 'oiseau': 'oiseaux',
  'nac': 'NAC', 'ovin': 'ovins', 'caprin': 'caprins', 'porcin': 'porcins',
};

String perimetreLabel(Map<String, dynamic> t, {String? profilSource}) {
  final p = perimetreDe(t, profilSource: profilSource);
  final e = (t['espece'] ?? '').toString();
  final esp = e.isEmpty ? '' : ' (${_especesPluriel[e] ?? e})';
  final lieu = (t['lieu'] ?? '').toString();
  switch (p) {
    case 'locaux': return lieu.isNotEmpty ? 'Locaux : $lieu' : 'Locaux / matériel';
    case 'portee': return 'Portée$esp';
    case 'animal': return 'Animaux choisis$esp';
    case 'categorie':
      final c = t['cible_type'].toString();
      return '${kCategoriesProtocole.firstWhere((k) => k.$1 == c, orElse: () => (c, c)).$2}$esp';
    default: return 'Tout le cheptel$esp';
  }
}

const kRefEvents = <(String, String, String)>[
  ('manuel',       'Date choisie à l’application', 'Vous indiquez le jour J0'),
  ('saillie',      'Saillie',                      'J0 = date de la saillie'),
  ('mise_bas',     'Mise bas',                     'J0 = date de mise bas (prévue)'),
  ('naissance',    'Naissance',                    'J0 = date de naissance'),
  ('age_semaines', 'Âge des animaux',              'Chaque étape à un âge en semaines'),
];

String refEventLabel(String v) => kRefEvents.firstWhere((r) => r.$1 == v, orElse: () => (v, v, '')).$2;

const kActesSuggeres = <(String, String)>[
  ('vermifuge', 'Vermifuge'), ('vaccination', 'Vaccination'), ('antiparasitaire', 'Antiparasitaire'),
  ('traitement', 'Traitement'), ('visite', 'Visite vétérinaire'), ('alimentaire', 'Alimentaire'),
  ('toilettage', 'Toilettage'), ('peignage', 'Peignage'), ('nettoyage', 'Désinfection'),
  ('promenade', 'Promenade / Socialisation'),
];

/// Libellé lisible d'une action (code connu ou texte libre saisi).
String acteLabel(String? v) {
  if (v == null || v.isEmpty) return '';
  if (v == 'socialisation') return 'Promenade / Socialisation';
  if (v == 'autre') return 'Autre';
  return kActesSuggeres.firstWhere((a) => a.$1 == v, orElse: () => (v, v)).$2;
}

/// Saisie libre → code connu si elle correspond à une suggestion.
String acteDepuisSaisie(String s) {
  final t = s.trim();
  return kActesSuggeres.firstWhere(
    (a) => a.$2.toLowerCase() == t.toLowerCase() || a.$1 == t.toLowerCase(),
    orElse: () => (t, t),
  ).$1;
}

const kTranches = <String, String>{'matin': 'Matin', 'midi': 'Midi', 'apres_midi': 'Après-midi', 'soir': 'Soir'};

String quandLabel(Map<String, dynamic> e, String refEvent) {
  final age = (e['age_min_semaines'] as num?)?.toInt();
  if (refEvent == 'age_semaines' || (age != null && refEvent == 'naissance')) {
    final a = age ?? 0;
    return 'À $a semaine${a > 1 ? 's' : ''} d’âge';
  }
  final ref = switch (refEvent) {
    'saillie' => 'la saillie', 'mise_bas' => 'la mise bas', 'naissance' => 'la naissance', _ => 'la date de début',
  };
  final j = (e['jour_offset'] as num?)?.toInt() ?? 0;
  if (j == 0) return refEvent == 'manuel' ? 'Dès la date de début' : 'Le jour de $ref';
  return '$j jour${j > 1 ? 's' : ''} ${e['offset_direction'] == 'avant' ? 'avant' : 'après'} $ref';
}

String frequenceLabel(Map<String, dynamic> e) {
  final sem = (e['duree_semaines'] as num?)?.toInt() ?? 1;
  final jours = (e['duree_jours'] as num?)?.toInt() ?? 1;
  final nb = (e['nb_fois_semaine'] as num?)?.toInt() ?? 1;
  final an = e['is_recurrent'] == true;
  return switch (e['frequence']) {
    'ponctuel' => jours > 1 ? '$jours jours de suite' : 'Une fois',
    'quotidien' => an ? 'Chaque jour (1 an)' : 'Chaque jour pendant $sem semaine${sem > 1 ? 's' : ''}',
    'hebdomadaire' => '$nb fois / semaine${an ? ' (1 an)' : ' pendant $sem semaine${sem > 1 ? 's' : ''}'}',
    'mensuel' => an ? 'Chaque mois (1 an)' : 'Chaque mois pendant $sem mois',
    _ => (e['frequence'] ?? '').toString(),
  };
}
