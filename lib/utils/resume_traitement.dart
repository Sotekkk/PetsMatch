import 'package:intl/intl.dart';

/// Résumé lisible d'un traitement (ou d'une étape d'une posologie
/// progressive) — miroir du site (resumeTraitement, mes-animaux/[id]).

String _jour(dynamic v) {
  final d = DateTime.tryParse(v?.toString() ?? '');
  return d == null ? '' : DateFormat('dd/MM/yyyy').format(d);
}

/// « Du 08/10/2026 au 15/10/2026 » / « Depuis le 08/10/2026 ».
String periodeTraitement(Map data) {
  final debut = _jour(data['date']), fin = _jour(data['date_fin']);
  if (debut.isNotEmpty && fin.isNotEmpty) return 'Du $debut au $fin';
  if (debut.isNotEmpty) return 'Depuis le $debut';
  return '';
}

/// « Tous les jours à 08:00, 19:00 · 7 jours » (rappels récurrents actifs).
String ligneRappelTraitement(Map data) {
  if (data['rappel_actif'] != true) return '';
  final freq = int.tryParse('${data['rappel_frequence_jours'] ?? ''}') ?? 1;
  final heures = data['rappel_heures'] is List
      ? (data['rappel_heures'] as List).map((h) => h.toString()).where((h) => h.isNotEmpty).toList()
      : <String>[];
  final duree = int.tryParse('${data['rappel_duree_jours'] ?? ''}');
  return [
    freq > 1 ? 'Tous les $freq jours' : 'Tous les jours',
    if (heures.isNotEmpty) 'à ${heures.join(', ')}',
  ].join(' ') + (duree != null && duree > 0 ? ' · $duree jours' : '');
}

/// « Étape 2 sur 3 » quand la prescription comporte plusieurs posologies
/// successives (notes « Phase 2/3 — … » écrites par le compte rendu vétérinaire).
String? etapeTraitement(Map data) {
  final m = RegExp(r'^Phase (\d+)/(\d+)').firstMatch(data['notes']?.toString() ?? '');
  return m == null ? null : 'Étape ${m.group(1)} sur ${m.group(2)}';
}

/// Notes sans le préfixe technique « Phase x/y — ».
String notesTraitement(Map data) =>
    (data['notes']?.toString() ?? '').replaceFirst(RegExp(r'^Phase \d+/\d+( — )?'), '').trim();

/// Lignes du résumé : étape, posologie, période, rappels.
List<String> resumeTraitement(Map data) => [
      etapeTraitement(data) ?? '',
      data['posologie']?.toString().trim() ?? '',
      periodeTraitement(data),
      ligneRappelTraitement(data),
    ].where((l) => l.isNotEmpty).toList();
