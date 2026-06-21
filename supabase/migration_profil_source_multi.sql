-- Isolation multi-profil : distinguer les données éleveur vs association
-- sur un même compte (uid identique).
-- À exécuter dans Supabase Dashboard → SQL Editor

ALTER TABLE taches_elevage         ADD COLUMN IF NOT EXISTS profil_source TEXT DEFAULT 'eleveur';
ALTER TABLE plan_templates         ADD COLUMN IF NOT EXISTS profil_source TEXT DEFAULT 'eleveur';
ALTER TABLE plans_actifs           ADD COLUMN IF NOT EXISTS profil_source TEXT DEFAULT 'eleveur';
ALTER TABLE plan_taches            ADD COLUMN IF NOT EXISTS profil_source TEXT DEFAULT 'eleveur';
ALTER TABLE certificats_engagement ADD COLUMN IF NOT EXISTS profil_source TEXT DEFAULT 'eleveur';
ALTER TABLE registre_sanitaire     ADD COLUMN IF NOT EXISTS profil_source TEXT DEFAULT 'eleveur';

-- Index pour les requêtes filtrées par profil
CREATE INDEX IF NOT EXISTS idx_taches_profil     ON taches_elevage(uid_eleveur, profil_source);
CREATE INDEX IF NOT EXISTS idx_templates_profil  ON plan_templates(uid_eleveur, profil_source);
CREATE INDEX IF NOT EXISTS idx_certifs_profil    ON certificats_engagement(cedant_uid, profil_source);
