// Espace pension d'un employé autorisé (« Planning pension » =
// read_planning_pension, lecture du registre ouverte par la RLS
// pension_entrees_employe_read_planning) : pensionnaires présents, arrivées
// et départs du jour. Scopé sur le profil pension de la relation, jamais sur
// le seul uid de l'employeur.
// Miroir site : website/src/lib/pensionnaires-employe.ts.
import 'package:supabase_flutter/supabase_flutter.dart';

String _t(Object? v) => v == null ? '' : v.toString().trim();
String _jour(Object? v) => _t(v).length >= 10 ? _t(v).substring(0, 10) : _t(v);

/// Séjours en cours ou attendus aujourd'hui, répartis pour l'employé.
class EspacePension {
  /// Présents (arrivée enregistrée, ou séjour commencé un jour passé).
  final List<Map<String, dynamic>> presents;
  /// Attendus aujourd'hui, arrivée pas encore enregistrée.
  final List<Map<String, dynamic>> arrivees;
  /// Présents dont le départ est prévu aujourd'hui (ou en retard).
  final List<Map<String, dynamic>> departs;
  const EspacePension({this.presents = const [], this.arrivees = const [], this.departs = const []});
}

/// Chaque séjour (ligne complète de pension_entrees, pour enregistrer
/// arrivée / départ) reçoit en plus `logement` (nom) et `photo_url` si lisibles.
Future<EspacePension> chargerEspacePension(String pensionProfileId) async {
  if (pensionProfileId.isEmpty) return const EspacePension();
  final supa = Supabase.instance.client;
  final auj = DateTime.now().toIso8601String().substring(0, 10);
  final rows = List<Map<String, dynamic>>.from(await supa.from('pension_entrees').select()
      .eq('pro_profile_id', pensionProfileId).eq('statut', 'en_pension'));
  final enCours = rows.where((e) => e['arrivee_reelle_le'] != null || _jour(e['date_entree']).compareTo(auj) <= 0).toList();
  if (enCours.isEmpty) return const EspacePension();

  // Photos des fiches et noms des logements : facultatifs (droits de lecture
  // variables), les listes s'affichent sans eux.
  final photos = <String, String>{};
  final ids = {for (final e in enCours) if (_t(e['animal_id']).isNotEmpty) _t(e['animal_id'])}.toList();
  if (ids.isNotEmpty) {
    try {
      for (final a in await supa.from('animaux').select('id, photo_url').inFilter('id', ids) as List) {
        if (_t(a['photo_url']).isNotEmpty) photos[_t(a['id'])] = _t(a['photo_url']);
      }
    } catch (_) {}
  }
  final logements = <String, String>{};
  final logIds = {for (final e in enCours) if (_t(e['logement_id']).isNotEmpty) _t(e['logement_id'])}.toList();
  if (logIds.isNotEmpty) {
    try {
      for (final l in await supa.from('enclos_chenil').select('id, nom').inFilter('id', logIds) as List) {
        logements[_t(l['id'])] = _t(l['nom']);
      }
    } catch (_) {}
  }
  final tous = [
    for (final e in enCours) {...e, 'photo_url': photos[_t(e['animal_id'])], 'logement': logements[_t(e['logement_id'])]},
  ]..sort((a, b) => _t(a['animal_nom']).toLowerCase().compareTo(_t(b['animal_nom']).toLowerCase()));
  final arrivees = tous.where((e) => e['arrivee_reelle_le'] == null && _jour(e['date_entree']) == auj).toList();
  final presents = tous.where((e) => !arrivees.contains(e)).toList();
  final departs = presents.where((e) => _jour(e['date_sortie_prevue']).isNotEmpty && _jour(e['date_sortie_prevue']).compareTo(auj) <= 0).toList();
  return EspacePension(presents: presents, arrivees: arrivees, departs: departs);
}
