-- Migration : backfill notifications.profile_id
-- Corrige la fuite cross-profil constatée sur les notifications employee_invite/
-- employee_revoked (jamais backfillées, contrairement au type 'like') et
-- inventaire_alerte (colonne profile_id jamais renseignée côté code avant
-- correction de lib/pages/eleveur/inventaire/inventaire_page.dart).
--
-- Déjà exécuté manuellement en production le 2026-08-05 (via l'API REST
-- Supabase, script ponctuel) — ce fichier documente le backfill pour
-- traçabilité et permet de le rejouer sur un autre environnement.

-- ── employee_invite / employee_revoked → profil "particulier" du destinataire ──
-- (règle établie : ces notifications sont toujours ancrées sur le profil
-- particulier, cf. migration_particulier_toujours_present.sql). Pas de filtre
-- is_main : un compte peut avoir son profil particulier en is_main = false.
UPDATE notifications n
SET profile_id = up.id::text
FROM user_profiles up
WHERE up.uid = n.uid
  AND up.profile_type = 'particulier'
  AND n.type IN ('employee_invite', 'employee_revoked')
  AND n.profile_id IS NULL;

-- ── inventaire_alerte → eleveur_profile_id de l'article concerné ──
-- Résolution précise via l'item source (data->>'itemId'), plus fiable qu'une
-- déduction par profil_type puisque l'alerte appartient à l'item lui-même.
UPDATE notifications n
SET profile_id = i.eleveur_profile_id::text
FROM inventaire_items i
WHERE i.id::text = (n.data->>'itemId')
  AND n.type = 'inventaire_alerte'
  AND n.profile_id IS NULL
  AND i.eleveur_profile_id IS NOT NULL;

-- Note : une ligne employee_invite reste volontairement non résolue si son
-- uid n'a plus aucune ligne dans user_profiles (compte supprimé/orphelin) —
-- rien de fiable à y assigner.

-- ── tache / tache_assignee → profil "particulier" de l'employé assigné ──
-- Même règle que employee_invite (destinataire = uid de l'employé).
UPDATE notifications n
SET profile_id = up.id::text
FROM user_profiles up
WHERE up.uid = n.uid
  AND up.profile_type = 'particulier'
  AND n.type IN ('tache', 'tache_assignee')
  AND n.profile_id IS NULL;

-- tache_validee (notification à l'éleveur/employeur) est VOLONTAIREMENT
-- exclu de ce backfill : sa résolution nécessiterait de joindre
-- taches_elevage.eleveur_profile_id via data->>'tacheId', mais cette colonne
-- s'est avérée incohérente sur les lignes concernées (elle pointe vers le
-- profil de l'employé assigné, pas celui de l'éleveur, sur au moins 2 tâches
-- vérifiées — id 24 et 25) : c'est un bug de données distinct dans
-- taches_elevage, pas dans notifications. À corriger séparément avant de
-- pouvoir backfiller tache_validee en confiance.
