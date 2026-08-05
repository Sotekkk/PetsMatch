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

-- tache_validee (notification à l'éleveur/employeur) : résolu via
-- taches_elevage.eleveur_profile_id (data->>'tacheId'). Nécessite d'abord
-- le correctif ci-dessous (bug lib/pages/eleveur/employes/employes_page.dart
-- _CreateTacheSheetState._save() : utilisait le profil actif de l'ACTEUR
-- courant au lieu de celui de l'éleveur quand un employé crée la tâche pour
-- son employeur).

-- ── Correctif des données : taches_elevage.eleveur_profile_id corrompu ──
-- Un employé créant une tâche pour son employeur (permission write_taches,
-- cf. employes_page.dart _buildTachesTab) enregistrait SON PROPRE
-- profile_id comme eleveur_profile_id au lieu de celui de l'éleveur.
-- Détecté et corrigé manuellement le 2026-08-05 sur les lignes 23, 24, 25,
-- 29, 30, 37 (uid_eleveur = YF9kR7jSTObnnw9lVj8gCl031rS2, mauvais profil =
-- celui de l'employé IfhRVwY55KUXW12lBG4D0bs0V383). Requête de détection
-- générique (à adapter/rejouer si besoin) :
--   SELECT t.id, t.uid_eleveur, t.eleveur_profile_id, up.uid AS profil_appartient_a
--   FROM taches_elevage t
--   JOIN user_profiles up ON up.id = t.eleveur_profile_id
--   WHERE up.uid <> t.uid_eleveur;
UPDATE taches_elevage t
SET eleveur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = t.uid_eleveur
  AND up.is_main = true
  AND t.eleveur_profile_id IN (
    SELECT t2.eleveur_profile_id FROM taches_elevage t2
    JOIN user_profiles up2 ON up2.id = t2.eleveur_profile_id
    WHERE up2.uid <> t2.uid_eleveur
  );

UPDATE notifications n
SET profile_id = t.eleveur_profile_id::text
FROM taches_elevage t
WHERE t.id::text = (n.data->>'tacheId')
  AND n.type = 'tache_validee'
  AND n.profile_id IS NULL
  AND t.eleveur_profile_id IS NOT NULL;
