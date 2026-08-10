-- ============================================================
-- PetsMatch — Onboarding par profil : table de progression
-- ============================================================
-- Une ligne par profil (user_profiles.id) qui suit l'avancement de son
-- parcours d'onboarding métier (voir docs/PetsMatch_Specs_Onboarding_Anatomie.md).
-- Remplace l'ancien onboarding local (SharedPreferences, 4 profils sur 10,
-- purement informatif) par un suivi persistant scopé par profile_id.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS onboarding_progress (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id      UUID NOT NULL UNIQUE REFERENCES user_profiles(id) ON DELETE CASCADE,
  completed_steps TEXT[] NOT NULL DEFAULT '{}',
  completed_at    TIMESTAMPTZ,
  skipped         BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- idx_onboarding_progress_profile_id est redondant avec la contrainte UNIQUE
-- ci-dessus (qui crée déjà un index) : volontairement omis.

-- Filtre rapide pour le bandeau de rappel dashboard ("X étapes restantes")
-- et pour la détection "première connexion" (pas de ligne du tout).
CREATE INDEX IF NOT EXISTS idx_onboarding_progress_incomplete
  ON onboarding_progress(profile_id) WHERE completed_at IS NULL;

-- RLS permissive : auth Firebase (pas Supabase Auth) → auth.uid() est toujours
-- null côté client, l'accès est scopé par profile_id côté application (jamais
-- par uid Firebase directement). Même pattern que admin_alerts.
ALTER TABLE onboarding_progress ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS onboarding_progress_all ON onboarding_progress;
CREATE POLICY onboarding_progress_all ON onboarding_progress USING (true) WITH CHECK (true);
