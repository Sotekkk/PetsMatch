-- ============================================================
-- PetsMatch V2 — Patch 07 : validation automatique des profils
-- ============================================================
-- Colonnes de résultat de vérification SIRET/RNA sur user_profiles
-- + table admin_alerts pour les cas nécessitant une revue manuelle
-- ============================================================

-- ── 1. Colonnes validation dans user_profiles ─────────────────
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS validation_status    TEXT    DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS validation_score     FLOAT,
  ADD COLUMN IF NOT EXISTS validation_reasons   JSONB,
  ADD COLUMN IF NOT EXISTS validation_api_data  JSONB,
  ADD COLUMN IF NOT EXISTS validation_checked_at TIMESTAMPTZ;

-- Contrainte sur les valeurs autorisées
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_validation_status'
  ) THEN
    ALTER TABLE user_profiles
      ADD CONSTRAINT chk_validation_status
      CHECK (validation_status IN ('pending','auto_validated','needs_review','manually_validated','rejected'));
  END IF;
END$$;

-- ── 2. Table admin_alerts ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS admin_alerts (
  id            UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  profile_id    UUID        REFERENCES user_profiles(id) ON DELETE CASCADE,
  uid           TEXT        NOT NULL,
  alert_type    TEXT        NOT NULL DEFAULT 'validation_required',
  status        TEXT        NOT NULL DEFAULT 'pending',
  data          JSONB,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  resolved_at   TIMESTAMPTZ,
  resolved_by   TEXT
);

ALTER TABLE admin_alerts
  ADD COLUMN IF NOT EXISTS resolved_note TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_alert_status'
  ) THEN
    ALTER TABLE admin_alerts
      ADD CONSTRAINT chk_alert_status
      CHECK (status IN ('pending','resolved','dismissed'));
  END IF;
END$$;

CREATE INDEX IF NOT EXISTS idx_admin_alerts_status     ON admin_alerts(status);
CREATE INDEX IF NOT EXISTS idx_admin_alerts_profile_id ON admin_alerts(profile_id);
CREATE INDEX IF NOT EXISTS idx_admin_alerts_uid        ON admin_alerts(uid);

-- RLS permissif (auth.uid() = null avec Firebase) — admin vérifie côté app
ALTER TABLE admin_alerts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admin_alerts_all ON admin_alerts;
CREATE POLICY admin_alerts_all ON admin_alerts USING (true) WITH CHECK (true);

-- ── 3. Marquage des profils sans validation nécessaire ────────
-- Les particuliers n'ont pas besoin de validation SIRET
UPDATE user_profiles
SET validation_status = 'auto_validated'
WHERE profile_type = 'particulier'
  AND validation_status = 'pending';
