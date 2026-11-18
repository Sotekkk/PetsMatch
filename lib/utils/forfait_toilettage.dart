// Toiletteur — forfaits « carte de N séances » (18/11/2026), comme le
// pet-sitter / l'éducateur :
//   • catalogue : forfaits_toilettage (Mes prestations) — nom, nombre de
//     séances, prix, prestation couverte (vide = toutes), validité en mois ;
//   • forfait choisi à la réservation (rdv.forfait_id) ou vendu depuis le
//     dossier de la séance → forfaits_souscrits (forfait_toilettage_id),
//     facturé UNE fois (facture_id) ; chaque séance est décomptée
//     (rdv.forfait_souscrit_id) et n'est plus facturée ; les séances suivantes
//     du client puisent dans la carte tant qu'il en reste.
// Miroir site : website/src/lib/forfait-toilettage.ts. Migration
// migration_toilettage_forfaits.sql (sans elle : rien ne change).
import 'package:supabase_flutter/supabase_flutter.dart';

class ForfaitToilettageClient {
  final Map<String, dynamic> souscription;
  final int total, utilises;
  const ForfaitToilettageClient(this.souscription, this.total, this.utilises);
  int get restants => (total - utilises).clamp(0, total);
  String get id => souscription['id'].toString();
  String get nom => souscription['nom_snapshot']?.toString() ?? 'Forfait';
  double get prix => (souscription['prix_snapshot'] as num?)?.toDouble() ?? 0;
  bool get facture => (souscription['facture_id']?.toString() ?? '').isNotEmpty;
  DateTime? get valideJusquAu => DateTime.tryParse(souscription['valide_jusqu_au']?.toString() ?? '');
  /// « Carte 5 toilettages · 3 séances restantes sur 5 »
  String get libelle => '$nom · $restants séance${restants > 1 ? 's' : ''} restante${restants > 1 ? 's' : ''} sur $total';
}

/// « 5 séances · 200 € · Toilettage complet »
String resumeForfaitToilettage(Map<String, dynamic> f, {String? prestationNom}) {
  final n = (f['nb_seances'] as num?)?.toInt() ?? 0;
  final prix = (f['prix'] as num?)?.toDouble() ?? 0;
  final v = (f['validite_mois'] as num?)?.toInt();
  return [
    '$n séance${n > 1 ? 's' : ''}',
    '${prix.toStringAsFixed(prix == prix.roundToDouble() ? 0 : 2).replaceAll('.', ',')} €',
    (prestationNom ?? '').isNotEmpty ? prestationNom! : 'toutes prestations',
    if (v != null && v > 0) 'valable $v mois',
  ].join(' · ');
}

/// Catalogue actif d'un toiletteur (profil), le plus ancien d'abord.
Future<List<Map<String, dynamic>>> forfaitsToilettageCatalogue(String proProfileId) async {
  if (proProfileId.isEmpty) return const [];
  try {
    final rows = await Supabase.instance.client.from('forfaits_toilettage').select()
        .eq('pro_profile_id', proProfileId).eq('actif', true).order('created_at');
    return [for (final r in rows as List) Map<String, dynamic>.from(r as Map)];
  } catch (_) {
    return const [];
  }
}

/// Séances décomptées d'une carte (RDV non annulés) ; met le compteur à jour.
Future<int> recompterForfaitToilettage(String fsId, int total) async {
  final supa = Supabase.instance.client;
  final l = await supa.from('rdv').select('id').eq('forfait_souscrit_id', fsId).not('statut', 'in', '(annule,refuse)');
  final n = (l as List).length;
  try {
    await supa.from('forfaits_souscrits').update({
      'nb_seances_utilisees': n,
      'statut': n >= total ? 'termine' : 'actif',
      'termine_le': n >= total ? DateTime.now().toUtc().toIso8601String() : null,
    }).eq('id', fsId);
  } catch (_) {}
  return n;
}

bool _couvre(Map<String, dynamic> fs, Map<String, dynamic> rdv) {
  final p = fs['prestation_toilettage_id']?.toString() ?? '';
  if (p.isNotEmpty && p != (rdv['prestation_id']?.toString() ?? '')) return false;
  final fin = DateTime.tryParse(fs['valide_jusqu_au']?.toString() ?? '');
  final jour = DateTime.tryParse(rdv['date_heure']?.toString() ?? '')?.toLocal() ?? DateTime.now();
  return fin == null || !DateTime(jour.year, jour.month, jour.day).isAfter(fin);
}

/// Carte du client pour ce RDV : celle déjà rattachée, sinon une carte en cours
/// (même toiletteur, prestation couverte, séances restantes, encore valable)
/// à laquelle la séance est rattachée, sinon la carte choisie à la réservation
/// (achetée maintenant). Idempotent : appelé à l'ouverture du dossier.
Future<ForfaitToilettageClient?> rattacherForfaitToilettage(Map<String, dynamic> rdvIn) async {
  final supa = Supabase.instance.client;
  try {
    final rdv = await supa.from('rdv')
        .select('id, statut, date_heure, prestation_id, forfait_id, forfait_souscrit_id, forfait_exclu, client_uid, client_profile_id, pro_uid, pro_profile_id, animal_id')
        .eq('id', rdvIn['id']).maybeSingle();
    if (rdv == null) return null;
    final pid = rdv['pro_profile_id']?.toString() ?? '';
    final cpid = rdv['client_profile_id']?.toString() ?? '';
    final cuid = rdv['client_uid']?.toString() ?? '';
    final deja = rdv['forfait_souscrit_id']?.toString() ?? '';
    Map<String, dynamic>? fs;
    if (deja.isNotEmpty) {
      fs = await supa.from('forfaits_souscrits').select().eq('id', deja).not('forfait_toilettage_id', 'is', null).maybeSingle();
      if (fs == null) return null; // forfait d'un autre métier
    } else {
      if (pid.isEmpty || (cpid.isEmpty && cuid.isEmpty)) return null;
      if (const {'annule', 'refuse'}.contains(rdv['statut']) || rdv['forfait_exclu'] == true) return null;
      var q = supa.from('forfaits_souscrits').select().eq('pro_profile_id', pid).not('forfait_toilettage_id', 'is', null).eq('statut', 'actif');
      q = cpid.isNotEmpty ? q.eq('client_profile_id', cpid) : q.eq('client_uid', cuid);
      for (final x in await q.order('souscrit_le') as List) {
        final s = Map<String, dynamic>.from(x as Map);
        if (!_couvre(s, rdv)) continue;
        final total = (s['nb_seances_total'] as num?)?.toInt() ?? 0;
        if (await recompterForfaitToilettage(s['id'].toString(), total) < total) { fs = s; break; }
      }
      // Sinon : carte choisie à cette réservation → achetée maintenant.
      final fid = rdv['forfait_id']?.toString() ?? '';
      if (fs == null && fid.isNotEmpty) {
        final f = await supa.from('forfaits_toilettage').select().eq('id', fid).maybeSingle();
        if (f != null) fs = await _souscrire(f, rdv);
      }
      if (fs == null) return null;
      await supa.from('rdv').update({'forfait_souscrit_id': fs['id']}).eq('id', rdv['id']);
    }
    final total = (fs['nb_seances_total'] as num?)?.toInt() ?? 0;
    final utilises = await recompterForfaitToilettage(fs['id'].toString(), total);
    return ForfaitToilettageClient(fs, total, utilises);
  } catch (_) {
    // Migration pas encore passée : rien à décompter.
    return null;
  }
}

Future<Map<String, dynamic>> _souscrire(Map<String, dynamic> f, Map<String, dynamic> rdv) async {
  final mois = (f['validite_mois'] as num?)?.toInt();
  final debut = DateTime.tryParse(rdv['date_heure']?.toString() ?? '')?.toLocal() ?? DateTime.now();
  final fin = mois != null && mois > 0 ? DateTime(debut.year, debut.month + mois, debut.day) : null;
  final cpid = rdv['client_profile_id']?.toString() ?? '';
  final cuid = rdv['client_uid']?.toString() ?? '';
  return Map<String, dynamic>.from(await Supabase.instance.client.from('forfaits_souscrits').insert({
    'forfait_toilettage_id': f['id'],
    if ((f['prestation_id']?.toString() ?? '').isNotEmpty) 'prestation_toilettage_id': f['prestation_id'],
    'pro_uid': rdv['pro_uid'], 'pro_profile_id': rdv['pro_profile_id'],
    if (cuid.isNotEmpty) 'client_uid': cuid,
    if (cpid.isNotEmpty) 'client_profile_id': cpid,
    if (rdv['animal_id'] != null) 'animal_id': rdv['animal_id'].toString(),
    'nom_snapshot': f['nom'] ?? 'Forfait',
    'nb_seances_total': (f['nb_seances'] as num?)?.toInt() ?? 1,
    'prix_snapshot': f['prix'],
    if (fin != null) 'valide_jusqu_au': '${fin.year.toString().padLeft(4, '0')}-${fin.month.toString().padLeft(2, '0')}-${fin.day.toString().padLeft(2, '0')}',
  }).select().single() as Map);
}

/// Vend une carte au client depuis le dossier : la séance du RDV est la
/// première décomptée.
Future<ForfaitToilettageClient?> vendreForfaitToilettage(Map<String, dynamic> rdvIn, Map<String, dynamic> forfait) async {
  final supa = Supabase.instance.client;
  final rdv = await supa.from('rdv')
      .select('id, date_heure, prestation_id, client_uid, client_profile_id, pro_uid, pro_profile_id, animal_id')
      .eq('id', rdvIn['id']).single();
  final fs = await _souscrire(forfait, rdv);
  await supa.from('rdv').update({'forfait_souscrit_id': fs['id'], 'forfait_id': forfait['id'], 'forfait_exclu': false}).eq('id', rdv['id']);
  final total = (fs['nb_seances_total'] as num?)?.toInt() ?? 0;
  return ForfaitToilettageClient(fs, total, await recompterForfaitToilettage(fs['id'].toString(), total));
}

/// La séance n'est plus décomptée de la carte (facturée à part).
Future<void> detacherForfaitToilettage(Map<String, dynamic> rdv, ForfaitToilettageClient f) async {
  await Supabase.instance.client.from('rdv').update({'forfait_souscrit_id': null, 'forfait_id': null, 'forfait_exclu': true}).eq('id', rdv['id']);
  await recompterForfaitToilettage(f.id, f.total);
}
