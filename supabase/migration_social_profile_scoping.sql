-- Pets Social — scoping par profil pour favoris et cosmétiques équipés.
-- Idempotent.

-- Favori posé par un profil précis (particulier / éleveur / pro…).
ALTER TABLE public.post_favorites
  ADD COLUMN IF NOT EXISTS author_profile_id uuid REFERENCES public.user_profiles(id);

CREATE INDEX IF NOT EXISTS idx_post_favorites_profile
  ON public.post_favorites (author_profile_id);

-- Cosmétique ÉQUIPÉ par profil : { "<profile_id>": "<cosmetic_id>" }.
-- `owned` reste global (acheté une fois pour le compte) ; `active_value` reste
-- comme repli (profil principal / lignes anciennes).
ALTER TABLE public.user_cosmetics
  ADD COLUMN IF NOT EXISTS active_by_profile jsonb DEFAULT '{}'::jsonb;
