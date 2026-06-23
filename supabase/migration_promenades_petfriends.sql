-- ============================================================
-- Migration : Promenades améliorations + PetFriends
-- Date      : 2026-06-23
-- Tickets   : PRO01, PFR01, PFR02
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- §17 PROMENADES — visibilité + invitations
-- ──────────────────────────────────────────────────────────

-- Visibilité sélective (publique / petfriends / invitation)
ALTER TABLE promenades
  ADD COLUMN IF NOT EXISTS visibilite TEXT DEFAULT 'publique';

-- Table invitations nominatives
CREATE TABLE IF NOT EXISTS promenades_invitations (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  promenade_id   UUID NOT NULL REFERENCES promenades(id) ON DELETE CASCADE,
  inviteur_uid   TEXT NOT NULL,
  invite_uid     TEXT NOT NULL,
  statut         TEXT DEFAULT 'en_attente',  -- en_attente | accepte | refuse
  vu_at          TIMESTAMPTZ,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(promenade_id, invite_uid)
);

CREATE INDEX IF NOT EXISTS idx_prom_inv_promenade ON promenades_invitations (promenade_id);
CREATE INDEX IF NOT EXISTS idx_prom_inv_invite    ON promenades_invitations (invite_uid, statut);

-- RLS promenades_invitations (permissive — Firebase Auth ne fournit pas auth.uid())
ALTER TABLE promenades_invitations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "prom_inv_select" ON promenades_invitations;
CREATE POLICY "prom_inv_select" ON promenades_invitations
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "prom_inv_insert" ON promenades_invitations;
CREATE POLICY "prom_inv_insert" ON promenades_invitations
  FOR INSERT WITH CHECK (inviteur_uid IS NOT NULL);

DROP POLICY IF EXISTS "prom_inv_update" ON promenades_invitations;
CREATE POLICY "prom_inv_update" ON promenades_invitations
  FOR UPDATE USING (true);

DROP POLICY IF EXISTS "prom_inv_delete" ON promenades_invitations;
CREATE POLICY "prom_inv_delete" ON promenades_invitations
  FOR DELETE USING (true);

-- ──────────────────────────────────────────────────────────
-- §18 PETFRIENDS — relations sociales entre propriétaires
-- ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS petfriends (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid_demandeur   TEXT NOT NULL,
  uid_recepteur   TEXT NOT NULL,
  statut          TEXT DEFAULT 'en_attente',  -- en_attente | accepte | refuse
  vu_at           TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(uid_demandeur, uid_recepteur)
);

CREATE INDEX IF NOT EXISTS idx_pf_demandeur ON petfriends (uid_demandeur, statut);
CREATE INDEX IF NOT EXISTS idx_pf_recepteur ON petfriends (uid_recepteur, statut);

-- RLS petfriends (permissive)
ALTER TABLE petfriends ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pf_select" ON petfriends;
CREATE POLICY "pf_select" ON petfriends
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "pf_insert" ON petfriends;
CREATE POLICY "pf_insert" ON petfriends
  FOR INSERT WITH CHECK (uid_demandeur IS NOT NULL);

DROP POLICY IF EXISTS "pf_update" ON petfriends;
CREATE POLICY "pf_update" ON petfriends
  FOR UPDATE USING (true);

DROP POLICY IF EXISTS "pf_delete" ON petfriends;
CREATE POLICY "pf_delete" ON petfriends
  FOR DELETE USING (true);

-- Visibilité animal côté PetFriends
ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS visible_petfriends BOOLEAN DEFAULT false;
