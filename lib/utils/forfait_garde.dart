// Pet-sitter — forfaits achetés (packs de visites, promenades ou jours de
// garde) et acomptes (13/11/2026), comme le comportementaliste :
//   • forfait choisi à la réservation → forfaits_souscrits (forfait_garde_id),
//     facturé UNE fois à l'achat (facture_id) ; chaque passage est décompté
//     (rdv.forfait_souscrit_id) et n'est plus facturé ; les gardes suivantes
//     du client puisent dans le forfait tant qu'il en reste ;
//   • acompte rattaché à la garde (factures.acompte_rdv_id), déduit de la
//     facture finale.
// Miroir site : website/src/lib/forfait-garde.ts. Migration
// migration_garde_acompte_forfaits.sql (sans elle : comportement d'avant).
import 'package:supabase_flutter/supabase_flutter.dart';

/// visite · promenade · garde_journee (type d'un forfait et d'un passage).
String typeGardeRdv(Map<String, dynamic> rdv) {
  final m = (rdv['motif'] ?? '').toString().toLowerCase();
  if (m.contains('promenade') || m.contains('balade')) return 'promenade';
  if (m.contains('garde') && m.contains('journ')) return 'garde_journee';
  return 'visite';
}

String uniteForfaitGarde(String? type, {bool pluriel = true}) => switch (type) {
      'promenade' => pluriel ? 'promenades' : 'promenade',
      'garde_journee' => pluriel ? 'jours de garde' : 'jour de garde',
      _ => pluriel ? 'visites' : 'visite',
    };

class ForfaitGardeClient {
  final Map<String, dynamic> souscription;
  final int total, utilises;
  /// Créé à l'instant (forfait choisi à cette réservation) : à facturer.
  final bool nouveau;
  final List<String> couverts; // RDV de cette garde décomptés du forfait
  const ForfaitGardeClient(this.souscription, this.total, this.utilises, this.nouveau, this.couverts);
  int get restants => (total - utilises).clamp(0, total);
  bool get facture => (souscription['facture_id']?.toString() ?? '').isNotEmpty;
  String get nom => souscription['nom_snapshot']?.toString() ?? 'Forfait';
  double get prix => (souscription['prix_snapshot'] as num?)?.toDouble() ?? 0;
  String get type => souscription['type_prestation_garde']?.toString() ?? 'visite';
}

/// Passages décomptés d'un forfait (RDV non annulés) ; met le compteur à jour.
Future<int> recompterForfaitGarde(String fsId, int total) async {
  final supa = Supabase.instance.client;
  final l = await supa.from('rdv').select('id').eq('forfait_souscrit_id', fsId).not('statut', 'in', '(annule,refuse)');
  final n = (l as List).length;
  try {
    await supa.from('forfaits_souscrits').update({
      'nb_seances_utilisees': n,
      'statut': n >= total ? 'termine' : 'actif',
      if (n >= total) 'termine_le': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', fsId);
  } catch (_) {}
  return n;
}

/// Rattache les passages de la garde au forfait du client : forfait en cours
/// (même type, places restantes) sinon celui choisi à la réservation (créé).
/// Idempotent : appelé à l'acceptation et à l'ouverture du dossier.
Future<ForfaitGardeClient?> rattacherForfaitGarde(List<Map<String, dynamic>> rdvsIn) async {
  if (rdvsIn.isEmpty) return null;
  final supa = Supabase.instance.client;
  try {
    final ids = [for (final r in rdvsIn) r['id'].toString()];
    final rdvs = [for (final r in await supa.from('rdv')
        .select('id, statut, motif, forfait_id, forfait_souscrit_id, est_essai, client_uid, client_profile_id, pro_uid, pro_profile_id, animal_id')
        .inFilter('id', ids).order('date_heure') as List) Map<String, dynamic>.from(r as Map)];
    if (rdvs.isEmpty) return null;
    final first = rdvs.first;
    final pid = first['pro_profile_id']?.toString() ?? '';
    final cpid = first['client_profile_id']?.toString() ?? '';
    final cuid = first['client_uid']?.toString() ?? '';
    if (pid.isEmpty || (cpid.isEmpty && cuid.isEmpty)) return null;
    final type = typeGardeRdv(first);

    Future<List<Map<String, dynamic>>> souscriptions({String? id}) async {
      var q = supa.from('forfaits_souscrits').select().eq('pro_profile_id', pid).not('forfait_garde_id', 'is', null);
      q = id != null ? q.eq('id', id) : (cpid.isNotEmpty ? q.eq('client_profile_id', cpid) : q.eq('client_uid', cuid));
      return [for (final x in await q.order('souscrit_le') as List) Map<String, dynamic>.from(x as Map)];
    }

    // Déjà rattachée (dossier rouvert) : son forfait.
    final deja = rdvs.map((r) => r['forfait_souscrit_id']?.toString() ?? '').firstWhere((s) => s.isNotEmpty, orElse: () => '');
    Map<String, dynamic>? fs;
    var nouveau = false;
    if (deja.isNotEmpty) {
      fs = (await souscriptions(id: deja)).firstOrNull;
    } else {
      // Forfait en cours du même type avec des passages restants.
      for (final s in await souscriptions()) {
        if (s['statut'] != 'actif' || (s['type_prestation_garde'] ?? 'visite') != type) continue;
        final total = (s['nb_seances_total'] as num?)?.toInt() ?? 0;
        if (await recompterForfaitGarde(s['id'].toString(), total) < total) { fs = s; break; }
      }
      // Sinon : forfait choisi à cette réservation → acheté maintenant.
      final fid = first['forfait_id']?.toString() ?? '';
      if (fs == null && fid.isNotEmpty) {
        final f = await supa.from('forfaits_garde').select().eq('id', fid).maybeSingle();
        if (f != null) {
          fs = Map<String, dynamic>.from(await supa.from('forfaits_souscrits').insert({
            'forfait_garde_id': fid,
            'type_prestation_garde': f['type_prestation'] ?? type,
            'pro_uid': first['pro_uid'], 'pro_profile_id': pid,
            if (cuid.isNotEmpty) 'client_uid': cuid,
            if (cpid.isNotEmpty) 'client_profile_id': cpid,
            if (first['animal_id'] != null) 'animal_id': first['animal_id'].toString(),
            'nom_snapshot': f['nom'] ?? 'Forfait',
            'nb_seances_total': (f['nb_visites'] as num?)?.toInt() ?? 1,
            'prix_snapshot': f['prix'],
          }).select().single() as Map);
          nouveau = true;
        }
      }
    }
    if (fs == null) return null;
    final total = (fs['nb_seances_total'] as num?)?.toInt() ?? 0;
    var utilises = await recompterForfaitGarde(fs['id'].toString(), total);
    // Décompte : passages pas encore rattachés, dans la limite du forfait.
    final aRattacher = <String>[];
    for (final r in rdvs) {
      if ((r['forfait_souscrit_id']?.toString() ?? '').isNotEmpty || r['est_essai'] == true) continue;
      if (const {'annule', 'refuse'}.contains(r['statut'])) continue;
      if (utilises + aRattacher.length >= total) break;
      aRattacher.add(r['id'].toString());
    }
    if (aRattacher.isNotEmpty) {
      await supa.from('rdv').update({'forfait_souscrit_id': fs['id']}).inFilter('id', aRattacher);
      utilises = await recompterForfaitGarde(fs['id'].toString(), total);
    }
    final couverts = [
      for (final r in rdvs)
        if (r['forfait_souscrit_id']?.toString() == fs['id'].toString() || aRattacher.contains(r['id'].toString())) r['id'].toString(),
    ];
    return ForfaitGardeClient(fs, total, utilises, nouveau || !((fs['facture_id']?.toString() ?? '').isNotEmpty), couverts);
  } catch (_) {
    // Migration pas encore passée : rien à décompter.
    return null;
  }
}

/// Acomptes (non annulés) demandés pour cette garde.
Future<List<Map<String, dynamic>>> acomptesGarde(List<String> rdvIds) async {
  if (rdvIds.isEmpty) return [];
  try {
    return [for (final f in await Supabase.instance.client.from('factures')
        .select('id, numero_affichage, total_ttc, statut').inFilter('acompte_rdv_id', rdvIds)
        .eq('type_facture', 'acompte').neq('statut', 'annulee').order('created_at') as List) Map<String, dynamic>.from(f as Map)];
  } catch (_) {
    return [];
  }
}
