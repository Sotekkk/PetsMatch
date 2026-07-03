-- ============================================================
-- PetsMatch — Fiche animal créée par un pro (ex : pension) sans
-- compte propriétaire + lien de réclamation par email.
-- uid_eleveur reste le "gestionnaire actuel" (garde le droit
-- d'éditer/voir la fiche tant que non réclamée). owner_uid est
-- le propriétaire réel, renseigné une fois la fiche réclamée.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS owner_uid TEXT REFERENCES users(uid) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_animaux_owner_uid ON animaux(owner_uid);

-- Lien optionnel entre un séjour pension et une vraie fiche animal
ALTER TABLE pension_entrees
  ADD COLUMN IF NOT EXISTS animal_id TEXT REFERENCES animaux(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS animal_claims (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  animal_id         TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  created_by_uid    TEXT NOT NULL,          -- le pro (pension) qui a créé la fiche
  email_destinataire TEXT,
  nom_destinataire  TEXT,
  tel_destinataire  TEXT,
  token             TEXT UNIQUE DEFAULT gen_random_uuid()::TEXT,
  statut            TEXT DEFAULT 'en_attente',  -- en_attente | reclame | expire
  claimed_by_uid    TEXT,
  claimed_at        TIMESTAMPTZ,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_animal_claims_animal ON animal_claims(animal_id);
CREATE INDEX IF NOT EXISTS idx_animal_claims_token ON animal_claims(token);

ALTER TABLE animal_claims ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select animal_claims by token or owner" ON animal_claims;
CREATE POLICY "Select animal_claims by token or owner" ON animal_claims
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Insert animal_claims" ON animal_claims;
CREATE POLICY "Insert animal_claims" ON animal_claims
  FOR INSERT WITH CHECK (created_by_uid IS NOT NULL AND length(created_by_uid) > 0);

DROP POLICY IF EXISTS "Update animal_claims by token" ON animal_claims;
CREATE POLICY "Update animal_claims by token" ON animal_claims
  FOR UPDATE USING (true) WITH CHECK (true);
