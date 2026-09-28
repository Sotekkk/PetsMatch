-- ═══════════════════════════════════════════════════════════════════════════
-- Extras bibliothèque musicale stories :
-- • story_music_tracks.categorie — pour une pastille colorée par ambiance
--   (comedy/electronic/epic/horror/romance/upbeat) dans le picker.
-- • stories.music_start_seconds — offset choisi par l'utilisateur dans le
--   morceau (façon TikTok/Instagram : on peut piocher n'importe quel
--   passage du morceau, pas forcément le début).
--
-- À exécuter dans Supabase SQL Editor (une seule fois).
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.story_music_tracks ADD COLUMN IF NOT EXISTS categorie text;
ALTER TABLE public.stories ADD COLUMN IF NOT EXISTS music_start_seconds numeric NOT NULL DEFAULT 0;
