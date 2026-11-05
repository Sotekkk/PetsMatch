import 'package:supabase_flutter/supabase_flutter.dart';

// Éducateur — forfaits de séances (forfaits_education → forfaits_souscrits) :
// type de séances couvertes, décompte d'une séance par RDV
// (rdv.forfait_souscrit_id : pas de facture à la séance), facture du forfait
// préparée à l'attribution (payé d'avance). Miroir site : lib/forfait-education.ts.

const kTypesSeances = [
  ('individuel', 'Séances individuelles'),
  ('collectif', 'Séances collectives'),
  ('mixte', 'Mixte (individuel et collectif)'),
];

String libelleTypeSeances(String? t) =>
    kTypesSeances.firstWhere((x) => x.$1 == t, orElse: () => kTypesSeances.last).$2;

/// Type du cours d'un RDV (catalogue) : collectif ou individuel (par défaut).
Future<String> typeSeanceRdv(Map<String, dynamic> rdv) async {
  final pid = rdv['prestation_id']?.toString();
  if (pid == null || pid.isEmpty) return 'individuel';
  final p = await Supabase.instance.client.from('prestations_education').select('type').eq('id', pid).maybeSingle();
  return p?['type'] == 'collectif' ? 'collectif' : 'individuel';
}

/// Forfait mixte avec un nombre de séances par type (individuelles / collectives).
bool estReparti(Map<String, dynamic> f) => f['nb_indiv_total'] != null || f['nb_coll_total'] != null;

int resteParType(Map<String, dynamic> f, String type) {
  final r = type == 'collectif'
      ? ((f['nb_coll_total'] as num?)?.toInt() ?? 0) - ((f['nb_coll_utilisees'] as num?)?.toInt() ?? 0)
      : ((f['nb_indiv_total'] as num?)?.toInt() ?? 0) - ((f['nb_indiv_utilisees'] as num?)?.toInt() ?? 0);
  return r < 0 ? 0 : r;
}

String _restantes(int n, int total) => '$n restante${n > 1 ? 's' : ''} sur $total';

/// « 3 séances restantes sur 5 », ou par type pour un forfait mixte réparti.
String libelleCompteurs(Map<String, dynamic> f) {
  if (estReparti(f)) {
    final ti = (f['nb_indiv_total'] as num?)?.toInt() ?? 0, tc = (f['nb_coll_total'] as num?)?.toInt() ?? 0;
    return [
      if (ti > 0) 'Individuelles : ${_restantes(resteParType(f, 'individuel'), ti)}',
      if (tc > 0) 'Collectives : ${_restantes(resteParType(f, 'collectif'), tc)}',
    ].join(' · ');
  }
  final r = seancesRestantes(f);
  return '$r séance${r > 1 ? 's' : ''} restante${r > 1 ? 's' : ''} sur ${(f['nb_seances_total'] as num?)?.toInt() ?? 0}';
}

bool forfaitCouvre(Map<String, dynamic> f, String typeCours) {
  if (estReparti(f)) return resteParType(f, typeCours) > 0;
  final t = f['type_seances']?.toString();
  return t == null || t.isEmpty || t == 'mixte' || t == typeCours;
}

int seancesRestantes(Map<String, dynamic> f) {
  final r = ((f['nb_seances_total'] as num?)?.toInt() ?? 0) - ((f['nb_seances_utilisees'] as num?)?.toInt() ?? 0);
  return r < 0 ? 0 : r;
}

List<Map<String, dynamic>> _detailRdv(Map<String, dynamic>? rdv) {
  final brut = rdv?['animaux_detail'];
  if (brut is! List || brut.length < 2) return [];
  return [for (final x in brut) if (x is Map) Map<String, dynamic>.from(x)];
}

Future<void> _retirerSeance(Map<String, dynamic> f, String typeCours, {required String animalId, required String animalNom, String? ownerUid}) async {
  final supa = Supabase.instance.client;
  final total = (f['nb_seances_total'] as num?)?.toInt() ?? 1;
  final used = ((f['nb_seances_utilisees'] as num?)?.toInt() ?? 0) + 1;
  final termine = used >= total;
  final reparti = estReparti(f);
  await supa.from('forfaits_souscrits').update({
    'nb_seances_utilisees': used,
    if (reparti && typeCours == 'collectif') 'nb_coll_utilisees': ((f['nb_coll_utilisees'] as num?)?.toInt() ?? 0) + 1,
    if (reparti && typeCours != 'collectif') 'nb_indiv_utilisees': ((f['nb_indiv_utilisees'] as num?)?.toInt() ?? 0) + 1,
    if (termine) 'statut': 'termine',
    if (termine) 'termine_le': DateTime.now().toUtc().toIso8601String(),
  }).eq('id', f['id']);
  if (ownerUid != null && (used == total - 1 || termine)) {
    await supa.from('notifications').insert({
      'uid': ownerUid, 'type': 'education_forfait_bas',
      'title': 'Forfait ${termine ? 'terminé' : 'bientôt terminé'} — $animalNom',
      'body': termine
          ? 'Toutes les séances du forfait « ${f['nom_snapshot']} » ont été utilisées.'
          : 'Il reste 1 séance sur le forfait « ${f['nom_snapshot']} ».',
      'data': {'animalId': animalId, 'url': '/mes-animaux/$animalId?tab=education'},
    });
  }
}

/// Décompte la séance du RDV (une seule fois par RDV) et prévient la famille quand il
/// ne reste qu'une séance ou plus aucune. Séance à plusieurs chiens : chacun sur son
/// propre forfait, noté dans rdv.animaux_detail. Renvoie les chiens sans forfait actif.
Future<List<String>> decompterSeanceForfait(Map<String, dynamic> f, String rdvId,
    {required String animalId, required String animalNom, String? ownerUid, String typeCours = 'individuel'}) async {
  final supa = Supabase.instance.client;
  final rdv = await supa.from('rdv').select('forfait_souscrit_id, animaux_detail, pro_profile_id').eq('id', rdvId).maybeSingle();
  if (rdv?['forfait_souscrit_id'] != null) return const [];
  final detail = _detailRdv(rdv);
  if (detail.isEmpty) {
    await _retirerSeance(f, typeCours, animalId: animalId, animalNom: animalNom, ownerUid: ownerUid);
    await supa.from('rdv').update({'forfait_souscrit_id': f['id'], 'forfait_type_decompte': estReparti(f) ? typeCours : null}).eq('id', rdvId);
    return const [];
  }
  final sansForfait = <String>[];
  Object? premier;
  for (final a in detail) {
    final idChien = a['id'].toString();
    final nomChien = (a['nom'] ?? '').toString();
    Map<String, dynamic>? fa = idChien == animalId ? f : null;
    if (fa == null) {
      var q = supa.from('forfaits_souscrits').select().eq('animal_id', idChien).eq('statut', 'actif');
      final pid = rdv?['pro_profile_id'];
      if (pid != null) q = q.eq('pro_profile_id', pid);
      fa = await q.order('souscrit_le', ascending: false).limit(1).maybeSingle();
    }
    if (fa == null) { sansForfait.add(nomChien); continue; }
    await _retirerSeance(fa, typeCours, animalId: idChien, animalNom: nomChien, ownerUid: ownerUid);
    a['forfait_souscrit_id'] = fa['id'];
    a['forfait_type_decompte'] = estReparti(fa) ? typeCours : null;
    premier ??= fa['id'];
    // Enregistré chien par chien : une erreur en cours de route ne fausse pas les soldes.
    await supa.from('rdv').update({
      'animaux_detail': detail, 'forfait_souscrit_id': premier, 'forfait_type_decompte': a['forfait_type_decompte'],
    }).eq('id', rdvId);
  }
  return sansForfait;
}

Future<void> _rendreSeance(Object fid, String? type) async {
  final supa = Supabase.instance.client;
  final f = await supa.from('forfaits_souscrits').select('nb_seances_utilisees, nb_indiv_utilisees, nb_coll_utilisees').eq('id', fid).maybeSingle();
  int moins(String c) { final v = ((f?[c] as num?)?.toInt() ?? 1) - 1; return v < 0 ? 0 : v; }
  await supa.from('forfaits_souscrits').update({
    'nb_seances_utilisees': moins('nb_seances_utilisees'),
    if (type == 'collectif') 'nb_coll_utilisees': moins('nb_coll_utilisees'),
    if (type == 'individuel') 'nb_indiv_utilisees': moins('nb_indiv_utilisees'),
    'statut': 'actif', 'termine_le': null,
  }).eq('id', fid);
}

/// Annule le décompte de la séance du RDV (rend la séance au forfait de chaque chien).
Future<void> annulerDecompteForfait(String rdvId) async {
  final supa = Supabase.instance.client;
  final rdv = await supa.from('rdv').select('forfait_souscrit_id, forfait_type_decompte, animaux_detail').eq('id', rdvId).maybeSingle();
  final fid = rdv?['forfait_souscrit_id'];
  if (fid == null) return;
  final detail = _detailRdv(rdv);
  final marques = detail.where((a) => a['forfait_souscrit_id'] != null).toList();
  if (marques.isEmpty) {
    await _rendreSeance(fid as Object, rdv?['forfait_type_decompte']?.toString());
    await supa.from('rdv').update({'forfait_souscrit_id': null, 'forfait_type_decompte': null}).eq('id', rdvId);
    return;
  }
  for (final a in marques) {
    await _rendreSeance(a['forfait_souscrit_id'] as Object, a['forfait_type_decompte']?.toString());
  }
  for (final a in detail) { a.remove('forfait_souscrit_id'); a.remove('forfait_type_decompte'); }
  await supa.from('rdv').update({'animaux_detail': detail, 'forfait_souscrit_id': null, 'forfait_type_decompte': null}).eq('id', rdvId);
}

/// Séance sans facture : tous les chiens décomptés (RDV ancien sans détail : le forfait du RDV).
bool seanceCouverte(Map<String, dynamic> rdv) {
  if (rdv['forfait_souscrit_id'] == null) return false;
  final detail = _detailRdv(rdv);
  return !detail.any((a) => a['forfait_souscrit_id'] != null) || detail.every((a) => a['forfait_souscrit_id'] != null);

}
