// Annuler une portée créée depuis une gestation (erreur de saisie) : fiches
// des petits supprimées (carnet, poids… en cascade), tâches de protocole de
// naissance retirées, gestation déliée (bouton « Créer la portée » de retour).
// Refusé dès qu'un petit a vécu quelque chose qu'on ne doit pas effacer :
// plus présent (cédé, décédé), cession ou transfert, autre propriétaire.
// Miroir site : website/src/lib/annuler-portee.ts.
import 'package:supabase_flutter/supabase_flutter.dart';

String _t(Object? v) => v == null ? '' : v.toString().trim();

class ApercuAnnulationPortee {
  final String porteeId;
  final List<String> ids;
  final List<String> noms;
  /// Raison du refus, sinon null (annulation possible).
  final String? blocage;
  const ApercuAnnulationPortee({required this.porteeId, this.ids = const [], this.noms = const [], this.blocage});
}

/// Petits de la portée de la gestation et, le cas échéant, ce qui empêche d'annuler.
Future<ApercuAnnulationPortee?> apercuAnnulationPortee(String gestationId) async {
  final supa = Supabase.instance.client;
  final g = await supa.from('gestations').select('animal_id, portee_id').eq('id', gestationId).maybeSingle();
  final porteeId = _t(g?['portee_id']);
  if (g == null || porteeId.isEmpty) return null;
  final mere = await supa.from('animaux').select('uid_eleveur').eq('id', _t(g['animal_id'])).maybeSingle();
  final eleveur = _t(mere?['uid_eleveur']);
  final petits = List<Map<String, dynamic>>.from(await supa.from('animaux')
      .select('id, nom, statut, uid_eleveur').eq('portee_id', porteeId) as List);
  final ids = [for (final p in petits) _t(p['id'])];
  final noms = [for (final p in petits) _t(p['nom']).isEmpty ? 'Sans nom' : _t(p['nom'])];
  String? blocage;
  final partis = petits.where((p) => _t(p['statut']).isNotEmpty && _t(p['statut']) != 'present').toList();
  if (partis.isNotEmpty) {
    blocage = '${partis.map((p) => _t(p['nom'])).join(', ')} ${partis.length > 1 ? "ne sont plus présents" : "n'est plus présent"} (cédé, décédé…).';
  } else if (petits.any((p) => eleveur.isNotEmpty && _t(p['uid_eleveur']) != eleveur)) {
    blocage = "Un petit n'appartient plus à l'élevage de la mère.";
  } else if (ids.isNotEmpty) {
    final cessions = await supa.from('cessions').select('animal_id').inFilter('animal_id', ids).limit(1) as List;
    final proprio = await supa.from('animaux_proprietes').select('animal_id, uid_proprio, date_fin').inFilter('animal_id', ids) as List;
    if (cessions.isNotEmpty) {
      blocage = 'Une cession a été préparée pour un petit.';
    } else if (proprio.any((r) => r['date_fin'] != null || (eleveur.isNotEmpty && _t(r['uid_proprio']) != eleveur))) {
      blocage = 'Un petit a changé de propriétaire.';
    }
  }
  return ApercuAnnulationPortee(porteeId: porteeId, ids: ids, noms: noms, blocage: blocage);
}

/// Annule après vérification ; renvoie un message d'erreur, ou null si c'est fait.
Future<String?> annulerPortee(String gestationId) async {
  final supa = Supabase.instance.client;
  final a = await apercuAnnulationPortee(gestationId);
  if (a == null) return "Cette gestation n'a pas de portée créée.";
  if (a.blocage != null) return 'Annulation impossible : ${a.blocage}';
  try {
    if (a.ids.isNotEmpty) {
      // Tâches liées aux petits (protocoles de naissance, tâches manuelles).
      try { await supa.from('plan_taches').delete().inFilter('animal_id', a.ids); } catch (_) {}
      try { await supa.from('plans_actifs').delete().inFilter('reference_id', a.ids); } catch (_) {}
      try { await supa.from('taches_elevage').delete().inFilter('animal_id', a.ids); } catch (_) {}
      // Fiches : seulement celles vérifiées (même portée, toujours présentes).
      await supa.from('animaux').delete().inFilter('id', a.ids).eq('portee_id', a.porteeId).or('statut.is.null,statut.eq.present');
    }
    await supa.from('gestations').update({'portee_id': null}).eq('id', gestationId);
    return null;
  } catch (e) {
    return "L'annulation n'a pas pu aller au bout : $e";
  }
}
