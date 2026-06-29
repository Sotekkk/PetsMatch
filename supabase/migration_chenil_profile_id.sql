-- Migration : chenil_boxes + enclos_chenil — ajout profile_id (user_profiles.id)
-- Même pattern que les autres tables : on garde l'ancien champ UID pour compatibilité

-- ── 1. chenil_boxes (association) ───────────────────────────────────────────
ALTER TABLE chenil_boxes
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE chenil_boxes cb
SET profile_id = up.id
FROM user_profiles up
WHERE up.uid = cb.association_uid
  AND up.is_main = true
  AND cb.profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_chenil_boxes_profile ON chenil_boxes(profile_id);

-- ── 2. enclos_chenil (éleveur + association + pension) ──────────────────────
ALTER TABLE enclos_chenil
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE enclos_chenil ec
SET profile_id = up.id
FROM user_profiles up
WHERE up.uid = ec.uid_eleveur
  AND up.is_main = true
  AND ec.profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_enclos_chenil_profile ON enclos_chenil(profile_id);
