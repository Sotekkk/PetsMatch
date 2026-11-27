// Portée créée depuis une gestation (mise bas réelle saisie) : mère = la
// femelle, père = le mâle des saillies du cycle (vide s'il y en a plusieurs :
// filiation à faire), race des parents si identique, date de naissance =
// date de mise bas, un petit par « Nb nés ». Lien gestation → portée :
// gestations.portee_id (migration_gestation_portee.sql).
// Miroir site : website/src/lib/portee-depuis-gestation.ts.
import 'package:supabase_flutter/supabase_flutter.dart';

String _t(Object? v) => v == null ? '' : v.toString().trim();

class PorteeDepuisGestation {
  final String gestationId;
  final String espece;
  final DateTime dateNaissance;
  final int nbNes;
  /// Fiche de la mère (id, nom, nom_pedigree, identification, race, date_naissance, uid_eleveur, profile_id).
  final Map<String, dynamic> mere;
  /// Père de l'élevage (même forme que la mère), si un seul mâle et qu'il est dans l'appli.
  final Map<String, dynamic>? pere;
  /// Père extérieur (saillie avec un mâle hors élevage).
  final String pereNom, perePuce;
  /// Race commune des parents ; vide si à préciser.
  final String race;
  /// « Race à préciser… », sinon null.
  final String? alerteRace;
  /// Plusieurs mâles sur le cycle : noms, père non rempli (filiation à faire).
  final List<String> malesMultiples;
  const PorteeDepuisGestation({
    required this.gestationId, required this.espece, required this.dateNaissance, required this.nbNes,
    required this.mere, this.pere, this.pereNom = '', this.perePuce = '', this.race = '',
    this.alerteRace, this.malesMultiples = const [],
  });

  bool get filiationAFaire => malesMultiples.length > 1;

  /// Mention posée sur les fiches et la portée quand le père est incertain.
  String get mentionFiliation =>
      'Père à confirmer : saillies de ${malesMultiples.join(' et ')}. Filiation (test ADN) à faire pour confirmer la parenté.';
}

List<DateTime> _dates(Map<String, dynamic> s) {
  final out = <DateTime>[];
  final raw = s['dates'];
  if (raw is List) {
    for (final v in raw) {
      final d = DateTime.tryParse(v.toString());
      if (d != null) out.add(d);
    }
  }
  if (out.isEmpty) {
    final d = DateTime.tryParse(_t(s['date']));
    if (d != null) out.add(d);
  }
  return out;
}

const _selAnimal = 'id, nom, nom_pedigree, sexe, espece, race, identification, date_naissance, uid_eleveur, profile_id';

/// null si la gestation n'a pas de mise bas réelle ou de nombre de nés.
Future<PorteeDepuisGestation?> preparerPorteeDepuisGestation(String gestationId) async {
  final supa = Supabase.instance.client;
  final g = await supa.from('gestations').select().eq('id', gestationId).maybeSingle();
  if (g == null) return null;
  final naissance = DateTime.tryParse(_t(g['date_naissance']));
  final nb = int.tryParse(_t(g['nb_nes'])) ?? 0;
  if (naissance == null || nb <= 0) return null;
  final mere = await supa.from('animaux').select(_selAnimal).eq('id', _t(g['animal_id'])).maybeSingle();
  if (mere == null) return null;

  // Saillies du cycle : celle d'où vient la gestation (id « <saillie>_gest »)
  // et toutes celles de la femelle autour de la conception (± 21 jours).
  final conception = DateTime.tryParse(_t(g['date'])) ?? naissance;
  final saillies = List<Map<String, dynamic>>.from(
      await supa.from('saillies').select().eq('animal_id', _t(g['animal_id'])) as List);
  final source = gestationId.endsWith('_gest') ? gestationId.substring(0, gestationId.length - 5) : '';
  final duCycle = saillies.where((s) =>
      _t(s['id']) == source ||
      _dates(s).any((d) => d.difference(conception).inDays.abs() <= 21)).toList();

  // Mâles distincts (fiche, sinon nom saisi).
  final males = <String, Map<String, dynamic>>{};
  for (final s in duCycle) {
    final id = _t(s['male_id']);
    final nom = _t(s['male_name']).isNotEmpty ? _t(s['male_name']) : _t(s['nom_partenaire']);
    final cle = id.isNotEmpty ? 'id:$id' : 'nom:${nom.toLowerCase()}';
    if (cle == 'nom:') continue;
    males.putIfAbsent(cle, () => {'id': id, 'nom': nom, 'puce': _t(s['ident_partenaire'])});
  }

  Map<String, dynamic>? pere;
  var pereNom = '', perePuce = '';
  final noms = [for (final m in males.values) _t(m['nom']).isEmpty ? 'mâle inconnu' : _t(m['nom'])];
  if (males.length == 1) {
    final m = males.values.first;
    if (_t(m['id']).isNotEmpty) {
      pere = await supa.from('animaux').select(_selAnimal).eq('id', _t(m['id'])).maybeSingle();
    }
    if (pere == null) { pereNom = _t(m['nom']); perePuce = _t(m['puce']); }
  }

  // Race : celle des parents si identique ; père incertain → race commune de
  // la mère et de tous les mâles possibles.
  final raceMere = _t(mere['race']);
  final racesPere = <String>{};
  if (pere != null) {
    racesPere.add(_t(pere['race']));
  } else if (males.length > 1) {
    for (final m in males.values) {
      if (_t(m['id']).isEmpty) { racesPere.add(''); continue; }
      final a = await supa.from('animaux').select('race').eq('id', _t(m['id'])).maybeSingle();
      racesPere.add(_t(a?['race']));
    }
  }
  final memeRace = raceMere.isNotEmpty && racesPere.isNotEmpty &&
      racesPere.every((r) => r.toLowerCase() == raceMere.toLowerCase());
  String? alerte;
  if (!memeRace) {
    alerte = racesPere.isEmpty || racesPere.contains('')
        ? 'Race à préciser : la race du père n\'est pas connue.'
        : 'Race à préciser : les parents n\'ont pas la même race.';
  }

  return PorteeDepuisGestation(
    gestationId: gestationId,
    espece: _t(mere['espece']).isEmpty ? 'chien' : _t(mere['espece']),
    dateNaissance: naissance,
    nbNes: nb > 30 ? 30 : nb,
    mere: Map<String, dynamic>.from(mere),
    pere: pere == null ? null : Map<String, dynamic>.from(pere),
    pereNom: pereNom,
    perePuce: perePuce,
    race: memeRace ? raceMere : '',
    alerteRace: alerte,
    malesMultiples: males.length > 1 ? noms : const [],
  );
}

/// Nom provisoire d'un petit (modifiable ensuite).
String nomProvisoirePetit(String espece, int i) {
  const mots = {'chien': 'Chiot', 'chat': 'Chaton', 'cheval': 'Poulain', 'lapin': 'Lapereau', 'ane': 'Ânon',
    'ovin': 'Agneau', 'caprin': 'Chevreau', 'porcin': 'Porcelet'};
  return '${mots[espece] ?? 'Petit'} $i';
}
