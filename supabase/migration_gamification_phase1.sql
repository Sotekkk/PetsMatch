-- ============================================================
-- Gamification communautaire — Phase 1 (boucle centrale)
-- Boucle : balade enregistrée → XP animal + palier d'objet évolutif
--          → flamme (série de régularité) → carte dans le feed
-- Comme le reste du projet, pas de RLS restrictive : Firebase Auth +
-- client anon Supabase, auth.uid() inexploitable → filtrage applicatif.
-- ============================================================

-- ── 1. Objet évolutif par animal (portée : par animal, pas par utilisateur) ──

ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS xp          INTEGER NOT NULL DEFAULT 0 CHECK (xp >= 0),
  ADD COLUMN IF NOT EXISTS object_tier TEXT NOT NULL DEFAULT 'decouverte'
    CHECK (object_tier IN ('decouverte', 'bronze', 'argent', 'or', 'legendaire'));

-- ── 2. Flamme (portée : par profil particulier, pas par animal) ─────────────
-- Un foyer avec plusieurs animaux ne doit pas sortir chacun séparément pour
-- maintenir sa flamme : elle représente l'engagement de la personne, pas
-- celui d'un animal en particulier.

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS streak_count                 INTEGER NOT NULL DEFAULT 0 CHECK (streak_count >= 0),
  ADD COLUMN IF NOT EXISTS streak_last_activity_date     DATE,
  ADD COLUMN IF NOT EXISTS streak_grace_used_this_week   BOOLEAN NOT NULL DEFAULT FALSE;

-- ── 3. species_object_tiers (table de référence, data-driven) ───────────────
-- Première brique du back-office administrable prévu pour les phases
-- suivantes : les paliers/seuils ne sont pas en dur dans le code Dart.

CREATE TABLE IF NOT EXISTS species_object_tiers (
  species          TEXT NOT NULL,
  tier             TEXT NOT NULL CHECK (tier IN ('decouverte', 'bronze', 'argent', 'or', 'legendaire')),
  xp_threshold     INTEGER NOT NULL DEFAULT 0 CHECK (xp_threshold >= 0),
  visual_asset_url TEXT,
  PRIMARY KEY (species, tier)
);

ALTER TABLE species_object_tiers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "species_object_tiers_select" ON species_object_tiers;
CREATE POLICY "species_object_tiers_select" ON species_object_tiers FOR SELECT USING (true);

INSERT INTO species_object_tiers (species, tier, xp_threshold) VALUES
  ('chien',  'decouverte', 0),   ('chien',  'bronze', 100), ('chien',  'argent', 300), ('chien',  'or', 700), ('chien',  'legendaire', 1500),
  ('chat',   'decouverte', 0),   ('chat',   'bronze', 100), ('chat',   'argent', 300), ('chat',   'or', 700), ('chat',   'legendaire', 1500),
  ('cheval', 'decouverte', 0),   ('cheval', 'bronze', 100), ('cheval', 'argent', 300), ('cheval', 'or', 700), ('cheval', 'legendaire', 1500),
  ('lapin',  'decouverte', 0),   ('lapin',  'bronze', 100), ('lapin',  'argent', 300), ('lapin',  'or', 700), ('lapin',  'legendaire', 1500),
  ('oiseau', 'decouverte', 0),   ('oiseau', 'bronze', 100), ('oiseau', 'argent', 300), ('oiseau', 'or', 700), ('oiseau', 'legendaire', 1500),
  ('nac',    'decouverte', 0),   ('nac',    'bronze', 100), ('nac',    'argent', 300), ('nac',    'or', 700), ('nac',    'legendaire', 1500)
ON CONFLICT (species, tier) DO NOTHING;

-- ── 4. activity_log (une ligne par activité éligible flamme/XP) ─────────────
-- Une seule action éligible en Phase 1 : la balade enregistrée.

CREATE TABLE IF NOT EXISTS activity_log (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid                TEXT NOT NULL,
  profile_id         UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  animal_id          TEXT REFERENCES animaux(id) ON DELETE SET NULL,
  activity_type      TEXT NOT NULL DEFAULT 'balade' CHECK (activity_type IN ('balade')),
  xp_earned          INTEGER NOT NULL DEFAULT 0 CHECK (xp_earned >= 0),
  distance_km        NUMERIC(6,2),
  duree_minutes      INTEGER,
  counts_for_streak  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at         TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_activity_log_uid        ON activity_log (uid);
CREATE INDEX IF NOT EXISTS idx_activity_log_animal_id  ON activity_log (animal_id);
CREATE INDEX IF NOT EXISTS idx_activity_log_created_at ON activity_log (created_at DESC);

ALTER TABLE activity_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "activity_log_select" ON activity_log;
CREATE POLICY "activity_log_select" ON activity_log FOR SELECT USING (true);

DROP POLICY IF EXISTS "activity_log_insert" ON activity_log;
CREATE POLICY "activity_log_insert" ON activity_log FOR INSERT WITH CHECK (uid IS NOT NULL);

-- ── 5. Cartes de feed « Balade terminée » / « Évolution débloquée » ─────────
-- Réutilise posts_socialmedia (même table que les posts classiques) avec un
-- discriminant post_type + une charge utile JSONB, sur le même principe que
-- notifications.type / notifications.data déjà en place ailleurs.

ALTER TABLE posts_socialmedia
  ADD COLUMN IF NOT EXISTS post_type TEXT NOT NULL DEFAULT 'user'
    CHECK (post_type IN ('user', 'balade_terminee', 'evolution')),
  ADD COLUMN IF NOT EXISTS data JSONB DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_posts_socialmedia_post_type ON posts_socialmedia (post_type);
