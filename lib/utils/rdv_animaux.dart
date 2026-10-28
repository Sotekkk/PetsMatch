// RDV à plusieurs animaux (vétérinaire, ostéo, toiletteur, éducateur) :
// rdv.animaux_detail = [{ id, nom, motif, motif_cle, duree_minutes, prestation_id?, prix? }]
// (migration_rdv_animaux_detail.sql). rdv.animal_id = le premier animal,
// rdv.duree_minutes = la somme des durées. Miroir site : lib/rdv-animaux.ts.

/// Détail par animal — vide pour un RDV à un seul animal.
List<Map<String, dynamic>> animauxDetailRdv(Map<String, dynamic> rdv) {
  final d = rdv['animaux_detail'];
  if (d is! List || d.length < 2) return const [];
  return [for (final x in d) if (x is Map) Map<String, dynamic>.from(x)];
}

String dureeRdvLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${h}h';
}

/// « Rex — Consultation · 30 min »
String ligneAnimalRdv(Map<String, dynamic> a) {
  final duree = (a['duree_minutes'] as num?)?.toInt();
  return [
    a['nom']?.toString() ?? '',
    [a['motif']?.toString() ?? '', if (duree != null) dureeRdvLabel(duree)].where((s) => s.isNotEmpty).join(' · '),
  ].where((s) => s.isNotEmpty).join(' — ');
}
