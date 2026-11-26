// Pensionnaires présents d'une pension, vus par un employé autorisé
// (« Planning pension » = read_planning_pension, lecture du registre ouverte
// par la RLS pension_entrees_employe_read_planning). Scopé sur le profil
// pension de la relation, jamais sur le seul uid de l'employeur.
// Miroir site : website/src/lib/pensionnaires-employe.ts.
import 'package:supabase_flutter/supabase_flutter.dart';

String _t(Object? v) => v == null ? '' : v.toString().trim();
String _jour(Object? v) => _t(v).length >= 10 ? _t(v).substring(0, 10) : _t(v);

/// Séjours en cours (arrivés, ou dont la date d'entrée est passée), triés par
/// nom. Chaque ligne : id, animal_id, animal_nom, espece, race, puce,
/// date_entree, date_sortie_prevue, logement (nom), photo_url (si lisible).
Future<List<Map<String, dynamic>>> pensionnairesPresents(String pensionProfileId) async {
  if (pensionProfileId.isEmpty) return [];
  final supa = Supabase.instance.client;
  final auj = DateTime.now().toIso8601String().substring(0, 10);
  final rows = List<Map<String, dynamic>>.from(await supa.from('pension_entrees')
      .select('id, pro_uid, animal_id, animal_nom, espece, race, puce, logement_id, date_entree, date_sortie_prevue, arrivee_reelle_le')
      .eq('pro_profile_id', pensionProfileId).eq('statut', 'en_pension'));
  final presents = rows.where((e) => e['arrivee_reelle_le'] != null || _jour(e['date_entree']).compareTo(auj) <= 0).toList();
  if (presents.isEmpty) return [];

  // Photos des fiches et noms des logements : facultatifs (droits de lecture
  // variables), la liste s'affiche sans eux.
  final photos = <String, String>{};
  final ids = {for (final e in presents) if (_t(e['animal_id']).isNotEmpty) _t(e['animal_id'])}.toList();
  if (ids.isNotEmpty) {
    try {
      for (final a in await supa.from('animaux').select('id, photo_url').inFilter('id', ids) as List) {
        if (_t(a['photo_url']).isNotEmpty) photos[_t(a['id'])] = _t(a['photo_url']);
      }
    } catch (_) {}
  }
  final logements = <String, String>{};
  final logIds = {for (final e in presents) if (_t(e['logement_id']).isNotEmpty) _t(e['logement_id'])}.toList();
  if (logIds.isNotEmpty) {
    try {
      for (final l in await supa.from('enclos_chenil').select('id, nom').inFilter('id', logIds) as List) {
        logements[_t(l['id'])] = _t(l['nom']);
      }
    } catch (_) {}
  }
  final res = [
    for (final e in presents)
      {
        ...e,
        'photo_url': photos[_t(e['animal_id'])],
        'logement': logements[_t(e['logement_id'])],
      },
  ]..sort((a, b) => _t(a['animal_nom']).toLowerCase().compareTo(_t(b['animal_nom']).toLowerCase()));
  return res;
}
