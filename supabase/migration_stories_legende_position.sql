-- ═══════════════════════════════════════════════════════════════════════════
-- Stories — position libre de la légende sur le média (glisser-déposer,
-- comme Instagram/Snapchat), coordonnées normalisées 0..1 (indépendantes de
-- la résolution de l'écran). Complète migration_stories.sql.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS legende_x double precision DEFAULT 0.5,  -- 0 = bord gauche, 1 = bord droit
  ADD COLUMN IF NOT EXISTS legende_y double precision DEFAULT 0.85; -- 0 = haut, 1 = bas
