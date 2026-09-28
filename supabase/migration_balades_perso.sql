-- ══════════════════════════════════════════════════════════════════════════
-- Balades perso (tracking GPS) — table + 2e flamme (partage)
-- ══════════════════════════════════════════════════════════════════════════
-- Remplace le formulaire manuel Phase 1 (enregistrer_balade_page.dart) par
-- un vrai suivi GPS en direct : la balade est tracée (route), peut avoir des
-- photos, et alimente toujours GamificationService.recordBalade (XP/palier/
-- flamme quotidienne, inchangé). Le partage (Story ou Post) déclenche une
-- 2e flamme distincte, gérée par les mêmes colonnes que streak_count mais
-- préfixées share_*.
--
-- animaux.id est TEXT (IDs legacy, pas des UUID) — animal_id ci-dessous est
-- donc TEXT, PAS une FK typée UUID (piège déjà documenté dans le projet).
-- ══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS balades_perso (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid           TEXT NOT NULL,
  profile_id    UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  animal_id     TEXT NOT NULL,
  statut        TEXT NOT NULL DEFAULT 'en_cours' CHECK (statut IN ('en_cours', 'terminee')),
  started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at      TIMESTAMPTZ,
  distance_m    NUMERIC,
  duree_s       INTEGER,
  -- Route : tableau JSON de points [{lat, lng, t}], t = timestamp ISO.
  route         JSONB NOT NULL DEFAULT '[]'::jsonb,
  photos        TEXT[] NOT NULL DEFAULT '{}',
  xp_earned     INTEGER,
  partage_story BOOLEAN NOT NULL DEFAULT FALSE,
  partage_post  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_balades_perso_uid     ON balades_perso(uid);
CREATE INDEX IF NOT EXISTS idx_balades_perso_animal   ON balades_perso(animal_id);
CREATE INDEX IF NOT EXISTS idx_balades_perso_profile  ON balades_perso(profile_id);

ALTER TABLE balades_perso ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "balades_perso_owner_all" ON balades_perso;
CREATE POLICY "balades_perso_owner_all" ON balades_perso
  FOR ALL USING ((auth.jwt() ->> 'sub') = uid)
  WITH CHECK ((auth.jwt() ->> 'sub') = uid);

-- 2e flamme : partage. Même mécanique que streak_count/streak_last_activity_date/
-- streak_grace_used_this_week (cf. GamificationService._applyStreak), déclenchée
-- uniquement par un partage explicite (Story ou Post depuis le récap de balade),
-- jamais par le post automatique de fin de balade.
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS share_streak_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS share_streak_last_activity_date DATE;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS share_streak_grace_used_this_week BOOLEAN NOT NULL DEFAULT FALSE;

-- Vérification
SELECT policyname, cmd FROM pg_policies WHERE tablename = 'balades_perso' ORDER BY cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK
-- ══════════════════════════════════════════════════════════════════════════
-- DROP TABLE IF EXISTS balades_perso;
-- ALTER TABLE user_profiles DROP COLUMN IF EXISTS share_streak_count;
-- ALTER TABLE user_profiles DROP COLUMN IF EXISTS share_streak_last_activity_date;
-- ALTER TABLE user_profiles DROP COLUMN IF EXISTS share_streak_grace_used_this_week;
