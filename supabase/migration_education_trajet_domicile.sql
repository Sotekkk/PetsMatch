-- ============================================================
-- PetsMatch — Éducateur/comportementaliste : trajet à domicile
-- Le pro décide quels créneaux acceptent une visite à domicile, et depuis
-- quelle adresse le trajet est calculé (son cabinet, ou "un autre domicile"),
-- avec possibilité de changer l'origine créneau par créneau.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE creneaux_pro
  ADD COLUMN IF NOT EXISTS domicile_ok BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS trajet_origine TEXT; -- 'cabinet' | 'autre_domicile' | NULL (= défaut du pro)

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS trajet_origine_defaut TEXT NOT NULL DEFAULT 'cabinet',
  ADD COLUMN IF NOT EXISTS autre_domicile_adresse TEXT,
  ADD COLUMN IF NOT EXISTS autre_domicile_lat NUMERIC,
  ADD COLUMN IF NOT EXISTS autre_domicile_lng NUMERIC;

ALTER TABLE user_profiles DROP CONSTRAINT IF EXISTS user_profiles_trajet_origine_defaut_check;
ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_trajet_origine_defaut_check
  CHECK (trajet_origine_defaut IN ('cabinet', 'autre_domicile'));
