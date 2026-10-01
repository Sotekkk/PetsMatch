import 'package:supabase_flutter/supabase_flutter.dart';

/// Recherche d'utilisateurs sans exposer les e-mails / téléphones des autres.
///
/// La vue `users_complet` masque l'e-mail de connexion et le téléphone d'un
/// particulier : un filtre `.eq('email', …)` dessus ne trouve donc plus
/// personne. La correspondance passe par la fonction SQL
/// `pm_trouver_utilisateur` : e-mail / téléphone EXACTS uniquement, et elle
/// ne renvoie que l'identité publique (uid, prénom, nom, élevage, photo).
/// Plus de recherche « contient » sur les e-mails (qui permettait de les
/// énumérer) : avec un « @ » → e-mail exact ; sinon → recherche par nom.

final _supa = Supabase.instance.client;

/// Utilisateur dont l'e-mail est exactement [email] (casse indifférente),
/// ou null. La ligne renvoyée contient aussi `email` = l'e-mail cherché.
Future<Map<String, dynamic>?> trouverUtilisateurParEmail(String email) async {
  final e = email.trim();
  if (e.isEmpty) return null;
  final res = await _supa.rpc('pm_trouver_utilisateur', params: {'p_email': e});
  final list = (res as List?) ?? const [];
  if (list.isEmpty) return null;
  return {...Map<String, dynamic>.from(list.first as Map), 'email': e.toLowerCase()};
}

/// Utilisateur dont le téléphone correspond (9 derniers chiffres), ou null.
Future<Map<String, dynamic>?> trouverUtilisateurParTelephone(String telephone) async {
  final res = await _supa.rpc('pm_trouver_utilisateur', params: {'p_telephone': telephone});
  final list = (res as List?) ?? const [];
  return list.isEmpty ? null : Map<String, dynamic>.from(list.first as Map);
}

/// Recherche « pendant la frappe » : e-mail exact si [query] contient un
/// « @ », sinon prénom / nom / nom d'élevage. [exclureUid] retire l'appelant.
Future<List<Map<String, dynamic>>> rechercherUtilisateurs(String query,
    {String? exclureUid, int limit = 6}) async {
  final q = query.trim();
  if (q.isEmpty) return [];
  if (q.contains('@')) {
    final u = await trouverUtilisateurParEmail(q);
    if (u == null || u['uid'] == exclureUid) return [];
    return [u];
  }
  final safe = q.replaceAll(RegExp(r'[,()%*]'), ' ');
  var req = _supa.from('users_complet')
      .select('uid, firstname, lastname, name_elevage, profile_picture_url, is_elevage, is_pro, is_association')
      .or('firstname.ilike.%$safe%,lastname.ilike.%$safe%,name_elevage.ilike.%$safe%');
  if (exclureUid != null) req = req.neq('uid', exclureUid);
  final rows = await req.limit(limit);
  return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
}
