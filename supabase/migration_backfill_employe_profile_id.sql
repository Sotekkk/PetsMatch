-- ============================================================
-- PetsMatch — Backfill employes.employe_profile_id manquant
-- ============================================================
-- Le fix du 2026-07-15 (voir migration_particulier_toujours_present.sql et
-- la regle "un profil particulier existe toujours") a corrige le code pour
-- que employes.employe_profile_id soit toujours renseigne a la creation.
-- Mais les lignes creees AVANT ce fix n'ont jamais ete backfillees : elles
-- n'ont que uid_employe (uid Firebase brut), pas employe_profile_id.
--
-- Consequence constatee : MesEmployeursPage (app) et /mes-employeurs (web)
-- filtrent strictement sur employe_profile_id des qu'un profil particulier
-- existe pour l'uid connecte -> l'employeur n'apparaissait plus du tout pour
-- les comptes concernes par une vieille ligne "employes", meme si la
-- relation existait bien en base.
--
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

UPDATE employes e
SET employe_profile_id = up.id
FROM user_profiles up
WHERE e.employe_profile_id IS NULL
  AND e.uid_employe IS NOT NULL
  AND up.uid = e.uid_employe
  AND up.profile_type = 'particulier';

-- ── Vérification ────────────────────────────────────────────
SELECT id, uid_employe, employe_profile_id, actif
FROM employes
WHERE employe_profile_id IS NULL AND uid_employe IS NOT NULL;
-- Les lignes restantes (s'il y en a) correspondent à des comptes sans
-- profil particulier du tout (créés avant migration_particulier_toujours_present.sql
-- et jamais backfillés côté user_profiles) — à traiter au cas par cas.
