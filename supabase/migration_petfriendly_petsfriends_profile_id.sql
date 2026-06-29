-- Migration : petfriendly_places, petfriendly_reviews, petfriendly_review_contests, petfriends
-- Ajout des colonnes profile_id (user_profiles.id)

-- ── 1. petfriendly_places — uid_pro → pro_profile_id ─────────────────────────
ALTER TABLE petfriendly_places
  ADD COLUMN IF NOT EXISTS pro_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE petfriendly_places p
SET pro_profile_id = up.id
FROM user_profiles up
WHERE up.uid = p.uid_pro
  AND up.is_main = true
  AND p.pro_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_petfriendly_places_pro_profile ON petfriendly_places(pro_profile_id);

-- ── 2. petfriendly_reviews — user_uid → user_profile_id ──────────────────────
ALTER TABLE petfriendly_reviews
  ADD COLUMN IF NOT EXISTS user_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE petfriendly_reviews r
SET user_profile_id = up.id
FROM user_profiles up
WHERE up.uid = r.user_uid
  AND up.is_main = true
  AND r.user_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_petfriendly_reviews_user_profile ON petfriendly_reviews(user_profile_id);

-- ── 3. petfriendly_review_contests — user_uid → user_profile_id ──────────────
ALTER TABLE petfriendly_review_contests
  ADD COLUMN IF NOT EXISTS user_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE petfriendly_review_contests c
SET user_profile_id = up.id
FROM user_profiles up
WHERE up.uid = c.user_uid
  AND up.is_main = true
  AND c.user_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_petfriendly_contests_user_profile ON petfriendly_review_contests(user_profile_id);

-- ── 4. petfriends — uid_demandeur/uid_recepteur → profile_id ─────────────────
ALTER TABLE petfriends
  ADD COLUMN IF NOT EXISTS demandeur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS recepteur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE petfriends f
SET demandeur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = f.uid_demandeur
  AND up.is_main = true
  AND f.demandeur_profile_id IS NULL;

UPDATE petfriends f
SET recepteur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = f.uid_recepteur
  AND up.is_main = true
  AND f.recepteur_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_petfriends_demandeur_profile ON petfriends(demandeur_profile_id);
CREATE INDEX IF NOT EXISTS idx_petfriends_recepteur_profile ON petfriends(recepteur_profile_id);
