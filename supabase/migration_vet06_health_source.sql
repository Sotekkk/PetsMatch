-- VET06: allow veterinarians to write to animal health records
-- Adds source + vet_id to all health tables so entries can be tagged
-- source: 'owner' (default) or 'veterinaire'
-- vet_id: Firebase UID of the vet who created the entry (NULL for owner entries)

ALTER TABLE vaccinations      ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'owner';
ALTER TABLE vaccinations      ADD COLUMN IF NOT EXISTS vet_id TEXT;

ALTER TABLE traitements       ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'owner';
ALTER TABLE traitements       ADD COLUMN IF NOT EXISTS vet_id TEXT;

ALTER TABLE visites            ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'owner';
ALTER TABLE visites            ADD COLUMN IF NOT EXISTS vet_id TEXT;

ALTER TABLE vermifuges         ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'owner';
ALTER TABLE vermifuges         ADD COLUMN IF NOT EXISTS vet_id TEXT;

ALTER TABLE antiparasitaires   ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'owner';
ALTER TABLE antiparasitaires   ADD COLUMN IF NOT EXISTS vet_id TEXT;

-- Backfill existing rows (all pre-existing entries belong to owner)
UPDATE vaccinations    SET source = 'owner' WHERE source IS NULL;
UPDATE traitements     SET source = 'owner' WHERE source IS NULL;
UPDATE visites         SET source = 'owner' WHERE source IS NULL;
UPDATE vermifuges      SET source = 'owner' WHERE source IS NULL;
UPDATE antiparasitaires SET source = 'owner' WHERE source IS NULL;
