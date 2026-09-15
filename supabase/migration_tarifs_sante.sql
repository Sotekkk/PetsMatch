-- ============================================================
-- PetsMatch — Mes tarifs (profil santé / ostéo·kiné)
-- Mirror de tarifs_education (migration_education_vitrine.sql) et
-- tarifs_garde (migration_garde_tarifs_clients.sql) : grille de tarifs
-- affichable sur la vitrine publique du pro, opt-in via *_visibles.
-- Colonnes lues/écrites par lib/pages/pro/pro_profile_edit.dart et
-- website/src/app/profil/page.tsx — absentes de user_profiles jusqu'ici,
-- ce qui bloquait l'enregistrement du profil pour tout profil `sante`.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS tarifs_sante            JSONB   DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS tarifs_sante_visibles    BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS tarifs_sante_extra       JSONB   DEFAULT '[]'::jsonb;

-- tarifs_sante         : prestations canoniques, ex. {"consultation": 45, "bilan": 60}
-- tarifs_sante_visibles: opt-in — tant que false, la vitrine est inchangée.
-- tarifs_sante_extra   : prestations libres nommées par le pro,
--   [{"label": "...", "prix": 0, "description": "..."}].
