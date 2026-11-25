// Animaux partis de la pension : dernier séjour terminé, aucun séjour en cours
// ou à venir, aucune demande de séjour ni RDV à venir, accès non redonné depuis
// la sortie. Retirés de « Accès fiche pensionnaire » (l'accès du propriétaire
// n'est pas supprimé).
// Miroir site : website/src/lib/pensionnaires-partis.ts.
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/rdv_animaux.dart';

String _t(Object? v) => v == null ? '' : v.toString().trim();
String _jour(Object? v) {
  final d = DateTime.tryParse(_t(v));
  if (d == null) return '';
  return d.toLocal().toIso8601String().substring(0, 10);
}

/// `accesLe` : animal_id → date de l'accès (granted_at, sinon created_at).
/// Une lecture en échec : aucun animal considéré comme parti.
Future<Set<String>> animauxPartis(String proProfileId, Map<String, String> accesLe) async {
  if (accesLe.isEmpty) return {};
  try {
    final supa = Supabase.instance.client;
    final ids = accesLe.keys.toList();
    final res = await Future.wait<List<Map<String, dynamic>>>([
      supa.from('pension_entrees').select('animal_id, statut, date_sortie_effective, date_sortie_prevue')
          .eq('pro_profile_id', proProfileId).inFilter('animal_id', ids),
      supa.from('pension_demandes').select('animal_id')
          .eq('pro_profile_id', proProfileId).eq('statut', 'demande').inFilter('animal_id', ids),
      supa.from('rdv').select('*').eq('pro_profile_id', proProfileId)
          .inFilter('statut', ['demande', 'contre_proposition', 'confirme'])
          .gte('date_heure', DateTime.now().toUtc().subtract(const Duration(days: 1)).toIso8601String()),
    ]);
    final attendus = <String>{
      for (final e in res[0]) if (e['statut'] == 'en_pension') _t(e['animal_id']),
      for (final d in res[1]) _t(d['animal_id']),
      for (final r in res[2]) ...idsAnimauxRdv(r),
    };
    final sortie = <String, String>{};
    for (final e in res[0]) {
      if (e['statut'] != 'sorti') continue;
      final id = _t(e['animal_id']);
      var j = _jour(e['date_sortie_effective']);
      if (j.isEmpty) j = _jour(e['date_sortie_prevue']);
      if (j.compareTo(sortie[id] ?? '') >= 0) sortie[id] = j;
    }
    return {
      for (final s in sortie.entries)
        if (!attendus.contains(s.key) && !(s.value.isNotEmpty && _jour(accesLe[s.key]).compareTo(s.value) > 0)) s.key,
    };
  } catch (_) {
    return {};
  }
}
