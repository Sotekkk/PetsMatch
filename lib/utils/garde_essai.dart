// Pet-sitter — visite d'essai d'un nouveau client (comme l'essai de la pension).
// Réglages dans user_profiles.tarifs_garde : essai_actif, essai (prix TTC),
// essai_duree (min), essai_obligatoire. RDV d'essai : rdv.est_essai ; résultat
// posé par le pet-sitter (rdv.essai_resultat). Miroir site : lib/garde-essai.ts.
import 'package:supabase_flutter/supabase_flutter.dart';

const kMotifEssai = "Visite d'essai";

class ReglagesEssai {
  final bool actif, obligatoire;
  final int prix, duree;
  const ReglagesEssai({this.actif = false, this.obligatoire = false, this.prix = 0, this.duree = 30});
  factory ReglagesEssai.depuis(Object? tarifs) {
    final t = tarifs is Map ? tarifs : const {};
    int n(Object? v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
    return ReglagesEssai(actif: n(t['essai_actif']) == 1, obligatoire: n(t['essai_obligatoire']) == 1,
        prix: n(t['essai']), duree: n(t['essai_duree']) > 0 ? n(t['essai_duree']) : 30);
  }
}

/// connu (déjà gardé ou essai concluant) · nouveau · en_attente · non_concluant.
Future<({String etat, String? date, String? motif})> etatEssaiClient(String clientUid, String proProfileId) async {
  final supa = Supabase.instance.client;
  try {
    final l = await supa.from('rdv')
        .select('statut, date_heure, est_essai, essai_resultat, essai_motif')
        .eq('client_uid', clientUid).eq('pro_profile_id', proProfileId)
        .inFilter('statut', ['demande', 'confirme', 'termine']).order('date_heure', ascending: false).limit(200);
    if (l.any((r) => (r['est_essai'] != true && ['confirme', 'termine'].contains(r['statut'])) || r['essai_resultat'] == 'concluant')) {
      return (etat: 'connu', date: null, motif: null);
    }
    final essai = l.where((r) => r['est_essai'] == true).firstOrNull;
    if (essai?['essai_resultat'] == 'non_concluant') {
      return (etat: 'non_concluant', date: essai!['date_heure']?.toString(), motif: essai['essai_motif']?.toString());
    }
    if (essai != null) return (etat: 'en_attente', date: essai['date_heure']?.toString(), motif: null);
    return (etat: 'nouveau', date: null, motif: null);
  } catch (_) {
    // migration_garde_essai.sql pas encore passée : règle d'avant.
    try {
      final d = await supa.from('rdv').select('id').eq('client_uid', clientUid).eq('pro_profile_id', proProfileId)
          .inFilter('statut', ['confirme', 'termine']).limit(1);
      return (etat: d.isNotEmpty ? 'connu' : 'nouveau', date: null, motif: null);
    } catch (_) {
      return (etat: 'connu', date: null, motif: null);
    }
  }
}

/// Résultat de l'essai posé par le pet-sitter, client prévenu.
Future<String?> poserResultatEssai(Map<String, dynamic> rdv, {required bool concluant, String? motif, required String proNom}) async {
  final supa = Supabase.instance.client;
  try {
    await supa.from('rdv').update({
      'essai_resultat': concluant ? 'concluant' : 'non_concluant',
      'essai_motif': (motif ?? '').trim().isEmpty ? null : motif!.trim(),
      'essai_resultat_le': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', rdv['id'].toString());
    final d = DateTime.tryParse(rdv['date_heure']?.toString() ?? '')?.toLocal();
    final jour = d == null ? '' : ' du ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    final m = (motif ?? '').trim();
    await supa.from('notifications').insert({
      'uid': rdv['client_uid'], 'type': 'rdv',
      'title': concluant ? 'Essai concluant' : 'Essai non concluant',
      'body': concluant
          ? "$proNom valide la visite d'essai$jour : vous pouvez réserver vos gardes."
          : "$proNom n'a pas validé la visite d'essai$jour.${m.isNotEmpty ? ' Motif : $m' : ''}",
      'data': {'rdv_id': rdv['id'].toString()}, 'read': false,
      if ((rdv['client_profile_id']?.toString() ?? '').isNotEmpty) 'profile_id': rdv['client_profile_id'],
    });
    return null;
  } catch (e) {
    return e.toString();
  }
}
