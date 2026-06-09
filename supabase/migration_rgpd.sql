-- RGPD05: track explicit CGU acceptance at signup
ALTER TABLE users ADD COLUMN IF NOT EXISTS cgu_accepted_at TIMESTAMPTZ;

-- Backfill: existing accounts are considered to have accepted (pre-RGPD enforcement)
-- Leave NULL so admin can identify pre-compliance accounts if needed
-- (do NOT backfill — NULL = account created before enforcement)
