// Exercices attribués (éducation / comportement) : durée et validation.
//  • étapes (etapes_snapshot) : validées une à une, dans l'ordre ;
//  • sinon nb_validations réussites, une par jour au plus (1 = « Marquer fait ») ;
//  • terminé (statut « fait ») au total atteint ; échéance = fin de la durée
//    (null = jusqu'à validation). Miroir site : website/src/lib/exercices-progression.ts.
import 'package:intl/intl.dart';

/// Durées proposées à l'attribution (jours ; null = jusqu'à validation).
const List<(String, int?)> kDureesExercice = [
  ('1 semaine', 7),
  ('2 semaines', 14),
  ('1 mois', 30),
  ("Jusqu'à validation", null),
];
const kDureeDefautJours = 14;

String _jour(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

String? echeanceDans(int? jours, [DateTime? depuis]) =>
    jours == null ? null : _jour((depuis ?? DateTime.now()).add(Duration(days: jours)));

class ProgressionExercice {
  final List<String> etapes;
  final int total, faites;
  final bool termine, echue, peutValider, dejaAujourdhui;
  const ProgressionExercice({required this.etapes, required this.total, required this.faites, required this.termine,
      required this.echue, required this.peutValider, required this.dejaAujourdhui});
  String? get prochaineEtape => faites < etapes.length ? etapes[faites] : null;
}

List<String> etapesDe(Map ex) => ((ex['etapes_snapshot'] as List?) ?? const [])
    .whereType<Map>().map((e) => (e['titre'] ?? '').toString().trim()).where((t) => t.isNotEmpty).toList();

List<String> _validations(Map ex) => ((ex['validations'] as List?) ?? const []).map((v) => v.toString()).toList();

ProgressionExercice progressionExercice(Map ex, [DateTime? maintenant]) {
  final now = maintenant ?? DateTime.now();
  final etapes = etapesDe(ex);
  final nb = (ex['nb_validations'] as num?)?.toInt() ?? 1;
  final total = etapes.isNotEmpty ? etapes.length : (nb < 1 ? 1 : nb);
  final vals = _validations(ex);
  final termine = ex['statut'] == 'fait';
  final faites = termine ? total : (vals.length > total ? total : vals.length);
  final aujourdhui = _jour(now);
  final deja = vals.contains(aujourdhui);
  final echeance = ex['echeance']?.toString();
  return ProgressionExercice(
    etapes: etapes, total: total, faites: faites, termine: termine,
    echue: echeance != null && echeance.isNotEmpty && echeance.compareTo(aujourdhui) < 0 && !termine,
    // Étapes : sans limite par jour ; réussites : une par jour.
    peutValider: !termine && (etapes.isNotEmpty || !deja),
    dejaAujourdhui: etapes.isEmpty && deja,
  );
}

/// Mise à jour à enregistrer pour valider (étape / réussite) ou annuler la dernière.
Map<String, dynamic> majValidationExercice(Map ex, {required bool valider, DateTime? maintenant}) {
  final now = maintenant ?? DateTime.now();
  final p = progressionExercice(ex, now);
  var vals = _validations(ex);
  // Ancien « fait » sans historique : le compter comme complet pour pouvoir annuler.
  if (p.termine && vals.length < p.total) {
    vals = List.generate(p.total, (i) => i < vals.length ? vals[i] : _jour(now));
  }
  if (valider) {
    vals.add(_jour(now));
  } else if (vals.isNotEmpty) {
    vals.removeLast();
  }
  final fait = vals.length >= p.total;
  return {
    'validations': vals,
    'statut': fait ? 'fait' : (vals.isNotEmpty ? 'en_cours' : 'a_faire'),
    'termine_le': fait ? now.toUtc().toIso8601String() : null,
    'updated_at': now.toUtc().toIso8601String(),
  };
}

/// « Jusqu'au 12 nov. », « Durée écoulée », « Jusqu'à validation » (null si terminé).
String? libelleDureeExercice(Map ex, [DateTime? maintenant]) {
  final p = progressionExercice(ex, maintenant);
  if (p.termine) return null;
  final e = DateTime.tryParse(ex['echeance']?.toString() ?? '');
  if (e == null) return "Jusqu'à validation";
  if (p.echue) return 'Durée écoulée';
  return "Jusqu'au ${DateFormat('d MMM', 'fr_FR').format(e)}";
}
