-- ═══════════════════════════════════════════════════════════════════════════
-- Pets Social — « Suivre » ne fonctionnait pas pour un compte multi-profils
--
-- Cause : la clé primaire de `follows` porte uniquement sur
-- (follower_uid, following_uid). Dès qu'UN profil du compte (ex : le profil
-- particulier) suit déjà quelqu'un, AUCUN autre profil du même compte (ex :
-- l'éleveur) ne peut le suivre à son tour : l'insert viole `follows_pkey`
-- (23505), l'erreur est avalée côté app, le bouton « Suivre » revient
-- silencieusement en arrière sans rien faire.
--
-- Fix : la clé primaire porte maintenant sur un nouvel id, et l'unicité réelle
-- se fait sur les 4 colonnes (follower_uid, following_uid,
-- follower_profile_id, following_profile_id) — un profil par cible.
-- À exécuter dans Supabase SQL Editor (une seule fois).
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.follows DROP CONSTRAINT IF EXISTS follows_pkey;
ALTER TABLE public.follows ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid();
UPDATE public.follows SET id = gen_random_uuid() WHERE id IS NULL;
ALTER TABLE public.follows ALTER COLUMN id SET NOT NULL;

DO $$ BEGIN
  ALTER TABLE public.follows ADD CONSTRAINT follows_pkey PRIMARY KEY (id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE public.follows
    ADD CONSTRAINT follows_unique_per_profile
    UNIQUE (follower_uid, following_uid, follower_profile_id, following_profile_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_follows_follower_uid  ON public.follows (follower_uid);
CREATE INDEX IF NOT EXISTS idx_follows_following_uid ON public.follows (following_uid);
