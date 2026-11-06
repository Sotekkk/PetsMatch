// Cocher / décocher une tâche simple depuis l'accueil éleveur.
// Miroir site : website/src/lib/valider-tache.ts (auteur de la validation +
// notification au gérant si un employé ou un cogérant valide). Une tâche
// cochée reste visible. Les RDV vétérinaires et les soins des protocoles ont
// leur propre circuit (récapitulatif, inscription au carnet) : pas ici.
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/exercice_tache.dart';

final _supa = Supabase.instance.client;

/// Tâche manuelle (taches_elevage) : a_faire ↔ fait. Renvoie le nouveau statut.
Future<String> basculerTacheManuelle(Map<String, dynamic> t, {required String uid, required String profileId}) async {
  final nouveau = t['statut'] == 'fait' ? 'a_faire' : 'fait';
  await _supa.from('taches_elevage').update(nouveau == 'fait'
      ? {'statut': nouveau, 'fait_par': uid, 'fait_par_profile_id': profileId.isEmpty ? null : profileId,
         'fait_a': DateTime.now().toUtc().toIso8601String()}
      : {'statut': nouveau, 'fait_par': null, 'fait_par_profile_id': null, 'fait_a': null}).eq('id', t['id']);
  // Exercice d'éducation : même effet que la coche de l'agenda.
  await validerExerciceDepuisTache(t['notes']?.toString(), nouveau == 'fait');
  final gerant = t['uid_eleveur']?.toString() ?? '';
  if (nouveau == 'fait' && gerant.isNotEmpty && gerant != uid) {
    try {
      final p = await _supa.from('user_profiles_complet').select('firstname,lastname,nom,profile_type')
          .eq('uid', uid).eq('is_main', true).maybeSingle();
      final nom = p == null ? 'Votre employé'
          : (p['profile_type'] == 'eleveur' ? (p['nom'] ?? 'Votre employé').toString()
              : ('${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim().isEmpty ? 'Votre employé' : '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim()));
      final epid = t['eleveur_profile_id']?.toString() ?? '';
      await _supa.from('notifications').insert({
        'uid': gerant, 'type': 'tache_validee', 'title': 'Tâche validée ✓',
        'body': '$nom a terminé : ${t['titre']}',
        'data': {'tacheId': t['id'], 'eleveurUid': gerant}, 'read': false,
        if (epid.isNotEmpty) 'profile_id': epid,
      });
    } catch (_) {}
  }
  return nouveau;
}

/// Tâche de protocole (plan_taches, hors soins) : en_attente ↔ fait.
Future<String> basculerRoutine(Map<String, dynamic> r, {required String uid, required String profileId}) async {
  final nouveau = r['statut'] == 'fait' ? 'en_attente' : 'fait';
  await _supa.from('plan_taches').update(nouveau == 'fait'
      ? {'statut': nouveau, 'valide_par': uid, 'valide_par_profile_id': profileId.isEmpty ? null : profileId,
         'valide_at': DateTime.now().toUtc().toIso8601String()}
      : {'statut': nouveau, 'valide_par': null, 'valide_par_profile_id': null, 'valide_at': null}).eq('id', r['id']);
  return nouveau;
}
