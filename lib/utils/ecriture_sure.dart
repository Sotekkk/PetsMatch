import 'package:supabase_flutter/supabase_flutter.dart';

/// « Mettre à jour si la ligne existe, sinon créer » — À UTILISER À LA PLACE
/// D'UN UPSERT sur `users` / `user_profiles`.
///
/// Depuis la phase 2 des données personnelles, les colonnes privées (email,
/// téléphone, adresse, lat / lng, is_admin…) ne sont plus lisibles via l'API.
/// Or un upsert (INSERT … ON CONFLICT DO UPDATE) exige de pouvoir LIRE les
/// colonnes qu'il met à jour → « permission denied » (inscription, édition de
/// profil…). Un UPDATE (relecture de la seule clé) puis un INSERT n'ont pas
/// cette contrainte.
///
/// [cles] : colonnes identifiant la ligne (ex. {'uid': uid} ou
/// {'uid': uid, 'profile_type': 'association'}). [colRetour] : colonne
/// lisible renvoyée (clé primaire). Retourne sa valeur.
Future<dynamic> ecrireLigne(
  String table,
  Map<String, dynamic> data,
  Map<String, Object> cles, {
  String colRetour = 'uid',
}) async {
  final supa = Supabase.instance.client;
  var maj = supa.from(table).update(data);
  cles.forEach((k, v) => maj = maj.eq(k, v));
  final existantes = await maj.select(colRetour);
  if ((existantes as List).isNotEmpty) return existantes.first[colRetour];
  final cree = await supa.from(table).insert({...cles, ...data}).select(colRetour).single();
  return cree[colRetour];
}
