-- Migration : réseaux sociaux éleveur (instagram, facebook, site_web)
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS instagram TEXT,
  ADD COLUMN IF NOT EXISTS facebook  TEXT,
  ADD COLUMN IF NOT EXISTS site_web  TEXT;
