-- ============================================================
-- PetsMatch — Tarifs clients personnalisés (petsitter/promeneur)
-- Permet à un profil garde de surcharger, pour un client donné,
-- le prix standard (tarifs_garde sur user_profiles) d'un type de
-- prestation. Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

-- Catalogue de base des tarifs garde (mirror tarifs_education, déjà
-- présent sur user_profiles pour education — absent pour garde jusqu'ici)
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS tarifs_garde JSONB DEFAULT '{}';

CREATE TABLE IF NOT EXISTS tarifs_clients_garde (
  id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  pro_uid           TEXT NOT NULL,
  pro_profile_id    UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  owner_uid         TEXT NOT NULL,
  owner_profile_id  UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  prestation_type   TEXT NOT NULL,
  prix              NUMERIC NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (pro_profile_id, owner_profile_id, prestation_type)
);

CREATE INDEX IF NOT EXISTS idx_tarifs_clients_garde_pro ON tarifs_clients_garde(pro_uid, pro_profile_id);
CREATE INDEX IF NOT EXISTS idx_tarifs_clients_garde_owner ON tarifs_clients_garde(owner_profile_id);

ALTER TABLE tarifs_clients_garde ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select tarifs_clients_garde" ON tarifs_clients_garde;
CREATE POLICY "Select tarifs_clients_garde" ON tarifs_clients_garde FOR SELECT USING (true);

DROP POLICY IF EXISTS "Insert tarifs_clients_garde" ON tarifs_clients_garde;
CREATE POLICY "Insert tarifs_clients_garde" ON tarifs_clients_garde
  FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND pro_profile_id IS NOT NULL AND owner_profile_id IS NOT NULL);

DROP POLICY IF EXISTS "Update tarifs_clients_garde" ON tarifs_clients_garde;
CREATE POLICY "Update tarifs_clients_garde" ON tarifs_clients_garde FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Delete tarifs_clients_garde" ON tarifs_clients_garde;
CREATE POLICY "Delete tarifs_clients_garde" ON tarifs_clients_garde FOR DELETE USING (true);
