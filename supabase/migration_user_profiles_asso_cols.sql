-- Colonnes supplémentaires pour le profil association (alignement app ↔ web)
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS profession_pro  TEXT,      -- nom du responsable
  ADD COLUMN IF NOT EXISTS ordre_veterinaire TEXT,    -- numéro RNA
  ADD COLUMN IF NOT EXISTS siret           TEXT,
  ADD COLUMN IF NOT EXISTS certifications  JSONB DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS desc_entreprise TEXT,
  ADD COLUMN IF NOT EXISTS phone           TEXT,
  ADD COLUMN IF NOT EXISTS rue             TEXT,
  ADD COLUMN IF NOT EXISTS code_postal     TEXT,
  ADD COLUMN IF NOT EXISTS pays            TEXT DEFAULT 'France',
  ADD COLUMN IF NOT EXISTS instagram       TEXT,
  ADD COLUMN IF NOT EXISTS facebook        TEXT,
  ADD COLUMN IF NOT EXISTS kbis_url        TEXT,
  ADD COLUMN IF NOT EXISTS acaced_doc_url  TEXT,
  ADD COLUMN IF NOT EXISTS especes_accueil TEXT[],
  ADD COLUMN IF NOT EXISTS capacite_accueil INTEGER;

-- RLS — toutes les opérations autorisées en anon (même logique que employes)
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_profiles_anon_select" ON user_profiles;
DROP POLICY IF EXISTS "user_profiles_anon_insert" ON user_profiles;
DROP POLICY IF EXISTS "user_profiles_anon_update" ON user_profiles;

CREATE POLICY "user_profiles_anon_select" ON user_profiles FOR SELECT USING (true);
CREATE POLICY "user_profiles_anon_insert" ON user_profiles FOR INSERT WITH CHECK (true);
CREATE POLICY "user_profiles_anon_update" ON user_profiles FOR UPDATE USING (true) WITH CHECK (true);
