-- ═══════════════════════════════════════════════════════════════════════════
-- Stories — mode "texte" (fond coloré/dégradé, sans photo/vidéo, comme
-- Instagram). Complète migration_stories.sql.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.stories
  ALTER COLUMN media_url DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS fond text; -- identifiant du fond choisi (ex. 'grad_sunset'), uniquement pour media_type='texte'
