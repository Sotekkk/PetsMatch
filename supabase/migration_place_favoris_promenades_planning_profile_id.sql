-- Migration : place_favoris, place_likes, plan_templates, plans_actifs,
--             promenades, promenades_participants, promenades_invitations
-- Ajout des colonnes profile_id (user_profiles.id)

-- ── 1. place_favoris — user_uid → user_profile_id ─────────────────────────────
ALTER TABLE place_favoris
  ADD COLUMN IF NOT EXISTS user_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE place_favoris f
SET user_profile_id = up.id
FROM user_profiles up
WHERE up.uid = f.user_uid
  AND up.is_main = true
  AND f.user_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_place_favoris_user_profile ON place_favoris(user_profile_id);

-- ── 2. place_likes — user_uid → user_profile_id ───────────────────────────────
ALTER TABLE place_likes
  ADD COLUMN IF NOT EXISTS user_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE place_likes l
SET user_profile_id = up.id
FROM user_profiles up
WHERE up.uid = l.user_uid
  AND up.is_main = true
  AND l.user_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_place_likes_user_profile ON place_likes(user_profile_id);

-- ── 3. plan_templates — uid_eleveur → eleveur_profile_id ──────────────────────
ALTER TABLE plan_templates
  ADD COLUMN IF NOT EXISTS eleveur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE plan_templates t
SET eleveur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = t.uid_eleveur
  AND up.is_main = true
  AND t.eleveur_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_plan_templates_eleveur_profile ON plan_templates(eleveur_profile_id);

-- ── 4. plans_actifs — uid_eleveur → eleveur_profile_id ───────────────────────
ALTER TABLE plans_actifs
  ADD COLUMN IF NOT EXISTS eleveur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE plans_actifs a
SET eleveur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = a.uid_eleveur
  AND up.is_main = true
  AND a.eleveur_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_plans_actifs_eleveur_profile ON plans_actifs(eleveur_profile_id);

-- ── 5. promenades — organisateur_uid → organisateur_profile_id ───────────────
ALTER TABLE promenades
  ADD COLUMN IF NOT EXISTS organisateur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE promenades p
SET organisateur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = p.organisateur_uid
  AND up.is_main = true
  AND p.organisateur_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_promenades_orga_profile ON promenades(organisateur_profile_id);

-- ── 6. promenades_participants — user_uid → user_profile_id ──────────────────
ALTER TABLE promenades_participants
  ADD COLUMN IF NOT EXISTS user_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE promenades_participants pp
SET user_profile_id = up.id
FROM user_profiles up
WHERE up.uid = pp.user_uid
  AND up.is_main = true
  AND pp.user_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_prom_part_user_profile ON promenades_participants(user_profile_id);

-- ── 7. promenades_invitations — inviteur_uid/invite_uid → profile_id ─────────
ALTER TABLE promenades_invitations
  ADD COLUMN IF NOT EXISTS inviteur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS invite_profile_id   UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE promenades_invitations i
SET inviteur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = i.inviteur_uid
  AND up.is_main = true
  AND i.inviteur_profile_id IS NULL;

UPDATE promenades_invitations i
SET invite_profile_id = up.id
FROM user_profiles up
WHERE up.uid = i.invite_uid
  AND up.is_main = true
  AND i.invite_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_prom_inv_inviteur_profile ON promenades_invitations(inviteur_profile_id);
CREATE INDEX IF NOT EXISTS idx_prom_inv_invite_profile   ON promenades_invitations(invite_profile_id);
