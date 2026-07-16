-- ============================================================
-- PetsMatch — Toiletteur : fiche client (préférences + historique +
-- photos avant/après). Une fiche par couple animal×profil toiletteur.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS fiches_toilettage (
  id                 UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  pro_uid            TEXT NOT NULL,
  pro_profile_id     UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
  animal_id          TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  client_uid         TEXT,
  client_profile_id  UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  shampooing_prefere TEXT,
  allergies          TEXT,
  coupe_habituelle   TEXT,
  notes              TEXT,
  created_at         TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(pro_profile_id, animal_id)
);

CREATE INDEX IF NOT EXISTS idx_fiches_toilettage_pro ON fiches_toilettage(pro_uid, pro_profile_id);
CREATE INDEX IF NOT EXISTS idx_fiches_toilettage_animal ON fiches_toilettage(animal_id);

ALTER TABLE fiches_toilettage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "fiches_toilettage_all" ON fiches_toilettage;
CREATE POLICY "fiches_toilettage_all" ON fiches_toilettage FOR ALL USING (true);

CREATE TABLE IF NOT EXISTS fiches_toilettage_photos (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  fiche_id   UUID NOT NULL REFERENCES fiches_toilettage(id) ON DELETE CASCADE,
  rdv_id     UUID REFERENCES rdv(id) ON DELETE SET NULL,
  type       TEXT NOT NULL CHECK (type IN ('avant', 'apres')),
  url        TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fiches_toilettage_photos_fiche ON fiches_toilettage_photos(fiche_id);

ALTER TABLE fiches_toilettage_photos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "fiches_toilettage_photos_all" ON fiches_toilettage_photos;
CREATE POLICY "fiches_toilettage_photos_all" ON fiches_toilettage_photos FOR ALL USING (true);
