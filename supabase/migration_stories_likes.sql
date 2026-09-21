-- ═══════════════════════════════════════════════════════════════════════════
-- Stories — likes (cœur, comme Instagram). Complète migration_stories.sql.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.story_likes (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id          uuid NOT NULL REFERENCES public.stories(id) ON DELETE CASCADE,
  uid               text NOT NULL,
  liker_profile_id  uuid REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (story_id, liker_profile_id)
);

CREATE INDEX IF NOT EXISTS idx_story_likes_story ON public.story_likes (story_id);
