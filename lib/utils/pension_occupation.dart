// Pension : un logement a-t-il encore de la place pour un séjour ? Utilisé à
// chaque attribution manuelle (arrivée, registre, logements) pour avertir
// avant de surbooker. Miroir site : lib/pension-occupation.ts.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _f = DateFormat('yyyy-MM-dd');

/// Nuits du séjour (arrivée incluse, départ exclu ; séjour d'un jour : ce jour).
List<String> _nuits(String debut, String? fin) {
  final d0 = DateTime.tryParse(debut.length >= 10 ? debut.substring(0, 10) : debut);
  if (d0 == null) return [];
  final f = (fin ?? '').length >= 10 ? fin!.substring(0, 10) : _f.format(d0);
  if (f.compareTo(_f.format(d0)) <= 0) return [_f.format(d0)];
  final out = <String>[];
  for (var d = d0; _f.format(d).compareTo(f) < 0 && out.length < 400; d = d.add(const Duration(days: 1))) {
    out.add(_f.format(d));
  }
  return out;
}

/// Message d'avertissement si le logement est complet sur une nuit du séjour
/// (null s'il reste de la place). [exclure] : séjours qui ne comptent pas.
Future<String?> avertissementLogementComplet(String logementId, Map<String, dynamic> sejour, {List<String> exclure = const []}) async {
  final debut = sejour['date_entree']?.toString() ?? '';
  if (logementId.isEmpty || debut.isEmpty) return null;
  try {
    final supa = Supabase.instance.client;
    final lg = await supa.from('enclos_chenil').select('nom, capacite').eq('id', logementId).maybeSingle();
    if (lg == null) return null;
    final capacite = (lg['capacite'] as num?)?.toInt() ?? 1;
    // Temps de désinfection entre deux séjours (Tarifs de la pension).
    var desinf = 0;
    final pid = sejour['pro_profile_id']?.toString() ?? '';
    if (pid.isNotEmpty) {
      final p = await supa.from('user_profiles').select('tarifs_pension').eq('id', pid).maybeSingle();
      desinf = (((p?['tarifs_pension'] as Map?)?['desinfection_jours'] as num?)?.toInt() ?? 0).clamp(0, 7);
    }
    String? plus(Object? iso) {
      final d = DateTime.tryParse(iso?.toString() ?? '');
      return d == null ? null : _f.format(d.add(Duration(days: desinf)));
    }
    final occ = await supa.from('pension_entrees').select('id, date_entree, date_sortie_prevue, seul_dans_logement')
        .eq('logement_id', logementId).eq('statut', 'en_pension');
    final autres = [for (final o in occ) if (!exclure.contains(o['id'].toString())) o];
    final complets = <String>[];
    for (final j in _nuits(debut, sejour['date_sortie_prevue']?.toString())) {
      // Occupé jusqu'au départ + désinfection.
      final ici = [for (final o in autres) if (_nuits(o['date_entree'].toString(), plus(o['date_sortie_prevue'])).contains(j)) o];
      final plein = ici.length + 1 > capacite || ici.any((o) => o['seul_dans_logement'] == true)
          || (sejour['seul_dans_logement'] == true && ici.isNotEmpty);
      if (plein) complets.add(j);
    }
    if (complets.isEmpty) return null;
    String fr(String j) => '${j.substring(8, 10)}/${j.substring(5, 7)}';
    final liste = complets.length > 4 ? '${complets.take(4).map(fr).join(', ')}…' : complets.map(fr).join(', ');
    return '${lg['nom']} est complet le $liste ($capacite place${capacite > 1 ? 's' : ''}${desinf > 0 ? ', désinfection de $desinf j comprise' : ''}) : choisissez un autre logement.';
  } catch (_) {
    return null;
  }
}

/// Logement complet sur une nuit du séjour : impossible (message). true = place libre.
Future<bool> confirmerLogementLibre(BuildContext context, String? logementId, Map<String, dynamic> sejour, {List<String> exclure = const []}) async {
  if ((logementId ?? '').isEmpty) return true;
  final msg = await avertissementLogementComplet(logementId!, sejour, exclure: exclure);
  if (msg == null) return true;
  if (context.mounted) {
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Logement complet', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      content: Text(msg, style: const TextStyle(fontFamily: 'Galey')),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Choisir un autre logement'))],
    ));
  }
  return false;
}
