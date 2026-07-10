-- ============================================================
-- PetsMatch — Gestion des clés (petsitter/promeneur)
-- Traçabilité des clés client détenues par un profil garde
-- (qui a la clé, où/comment y accéder, depuis quand).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS cles_clients (
  id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  pro_uid           TEXT NOT NULL,
  pro_profile_id    UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
  animal_id         UUID REFERENCES animaux(id) ON DELETE SET NULL,
  owner_uid         TEXT,
  owner_profile_id  UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  description       TEXT NOT NULL,
  statut            TEXT NOT NULL DEFAULT 'en_possession' CHECK (statut IN ('en_possession', 'rendue')),
  date_recuperation DATE,
  date_restitution  DATE,
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cles_clients_pro ON cles_clients(pro_uid, pro_profile_id);
CREATE INDEX IF NOT EXISTS idx_cles_clients_animal ON cles_clients(animal_id);

ALTER TABLE cles_clients ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select cles_clients" ON cles_clients;
CREATE POLICY "Select cles_clients" ON cles_clients FOR SELECT USING (true);

DROP POLICY IF EXISTS "Insert cles_clients" ON cles_clients;
CREATE POLICY "Insert cles_clients" ON cles_clients
  FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND pro_profile_id IS NOT NULL);

DROP POLICY IF EXISTS "Update cles_clients" ON cles_clients;
CREATE POLICY "Update cles_clients" ON cles_clients FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Delete cles_clients" ON cles_clients;
CREATE POLICY "Delete cles_clients" ON cles_clients FOR DELETE USING (true);
