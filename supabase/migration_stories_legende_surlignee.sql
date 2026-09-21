-- ═══════════════════════════════════════════════════════════════════════════
-- Stories — légende "surlignée" (fond blanc, texte noir, juste sur la zone de
-- texte — pas le fond entier de la story). Complète migration_stories.sql.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS legende_surlignee boolean DEFAULT false;
