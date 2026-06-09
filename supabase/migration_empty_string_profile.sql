-- Migrate NULL pro_profile_id → '' (empty string) for primary profiles
-- PostgreSQL unique constraints treat NULL as distinct (NULL != NULL), so upserts
-- with NULL in a unique key never trigger conflict detection. Using '' solves this.

-- Step 1: add column if not already present (idempotent)
ALTER TABLE creneaux_pro    ADD COLUMN IF NOT EXISTS pro_profile_id TEXT DEFAULT '';
ALTER TABLE rdv             ADD COLUMN IF NOT EXISTS pro_profile_id TEXT DEFAULT '';
ALTER TABLE vet_access_grants ADD COLUMN IF NOT EXISTS pro_profile_id TEXT DEFAULT '';
ALTER TABLE pension_acces   ADD COLUMN IF NOT EXISTS pro_profile_id TEXT DEFAULT '';
ALTER TABLE pension_entrees ADD COLUMN IF NOT EXISTS pro_profile_id TEXT DEFAULT '';
ALTER TABLE agenda_events   ADD COLUMN IF NOT EXISTS pro_profile_id TEXT DEFAULT '';

-- Step 2: migrate any pre-existing NULL values to ''
UPDATE creneaux_pro    SET pro_profile_id = '' WHERE pro_profile_id IS NULL;
UPDATE rdv             SET pro_profile_id = '' WHERE pro_profile_id IS NULL;
UPDATE vet_access_grants SET pro_profile_id = '' WHERE pro_profile_id IS NULL;
UPDATE pension_acces   SET pro_profile_id = '' WHERE pro_profile_id IS NULL;
UPDATE pension_entrees SET pro_profile_id = '' WHERE pro_profile_id IS NULL;
UPDATE agenda_events   SET pro_profile_id = '' WHERE pro_profile_id IS NULL;

-- Step 3: ensure default is '' (already set above, but explicit for clarity)
ALTER TABLE creneaux_pro    ALTER COLUMN pro_profile_id SET DEFAULT '';
ALTER TABLE rdv             ALTER COLUMN pro_profile_id SET DEFAULT '';
ALTER TABLE vet_access_grants ALTER COLUMN pro_profile_id SET DEFAULT '';
ALTER TABLE pension_acces   ALTER COLUMN pro_profile_id SET DEFAULT '';
ALTER TABLE pension_entrees ALTER COLUMN pro_profile_id SET DEFAULT '';
ALTER TABLE agenda_events   ALTER COLUMN pro_profile_id SET DEFAULT '';

-- statut_pro column for user_profiles (secondary profiles validation)
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS statut_pro TEXT DEFAULT 'en_attente';

-- creneaux_pro.statut now also accepts 'bloque' for unavailability blocks
-- (no DDL needed since statut is TEXT — valid values: 'disponible', 'bloque')
