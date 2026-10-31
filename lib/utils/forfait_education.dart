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

bool forfaitCouvre(Map<String, dynamic> f, String typeCours) {
  final t = f['type_seances']?.toString();
  return t == null || t.isEmpty || t == 'mixte' || t == typeCours;
}

int seancesRestantes(Map<String, dynamic> f) {
  final r = ((f['nb_seances_total'] as num?)?.toInt() ?? 0) - ((f['nb_seances_utilisees'] as num?)?.toInt() ?? 0);
  return r < 0 ? 0 : r;
}

/// Décompte la séance du RDV de ce forfait (une seule fois par RDV) et prévient
/// la famille quand il ne reste qu'une séance ou plus aucune.
Future<void> decompterSeanceForfait(Map<String, dynamic> f, String rdvId,
    {required String animalId, required String animalNom, String? ownerUid}) async {
  final supa = Supabase.instance.client;
  final rdv = await supa.from('rdv').select('forfait_souscrit_id').eq('id', rdvId).maybeSingle();
  if (rdv?['forfait_souscrit_id'] != null) return;
  final total = (f['nb_seances_total'] as num?)?.toInt() ?? 1;
  final used = ((f['nb_seances_utilisees'] as num?)?.toInt() ?? 0) + 1;
  final termine = used >= total;
  await supa.from('forfaits_souscrits').update({
    'nb_seances_utilisees': used,
    if (termine) 'statut': 'termine',
    if (termine) 'termine_le': DateTime.now().toUtc().toIso8601String(),
  }).eq('id', f['id']);
  await supa.from('rdv').update({'forfait_souscrit_id': f['id']}).eq('id', rdvId);
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

/// Annule le décompte de la séance du RDV (rend la séance au forfait).
Future<void> annulerDecompteForfait(String rdvId) async {
  final supa = Supabase.instance.client;
  final rdv = await supa.from('rdv').select('forfait_souscrit_id').eq('id', rdvId).maybeSingle();
  final fid = rdv?['forfait_souscrit_id'];
  if (fid == null) return;
  final f = await supa.from('forfaits_souscrits').select('nb_seances_utilisees').eq('id', fid).maybeSingle();
  final used = ((f?['nb_seances_utilisees'] as num?)?.toInt() ?? 1) - 1;
  await supa.from('forfaits_souscrits').update({'nb_seances_utilisees': used < 0 ? 0 : used, 'statut': 'actif', 'termine_le': null}).eq('id', fid);
  await supa.from('rdv').update({'forfait_souscrit_id': null}).eq('id', rdvId);
}
