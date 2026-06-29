-- Migration : inventaire — ajout profile_id (user_profiles.id)
-- Remplace uid_eleveur / uid_auteur (Firebase UIDs) par UUID user_profiles

-- ── inventaire_items ──────────────────────────────────────────────────────────
ALTER TABLE inventaire_items
  ADD COLUMN IF NOT EXISTS eleveur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE inventaire_items i
SET eleveur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = i.uid_eleveur
  AND up.is_main = true
  AND i.eleveur_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_inventaire_items_profile ON inventaire_items(eleveur_profile_id);

-- ── inventaire_mouvements ─────────────────────────────────────────────────────
ALTER TABLE inventaire_mouvements
  ADD COLUMN IF NOT EXISTS eleveur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS auteur_profile_id  UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE inventaire_mouvements m
SET eleveur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = m.uid_eleveur
  AND up.is_main = true
  AND m.eleveur_profile_id IS NULL;

UPDATE inventaire_mouvements m
SET auteur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = m.uid_auteur
  AND up.is_main = true
  AND m.auteur_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_inventaire_mvt_eleveur_profile ON inventaire_mouvements(eleveur_profile_id);
CREATE INDEX IF NOT EXISTS idx_inventaire_mvt_auteur_profile  ON inventaire_mouvements(auteur_profile_id);
