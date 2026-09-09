-- comptes_rendus : ajout du scoping par profil (comme ordonnances), +
-- assouplissement de owner_uid (peut être NULL si le propriétaire n'est pas
-- résolu — le compte rendu reste rattaché à l'animal). Idempotent.

ALTER TABLE public.comptes_rendus
  ADD COLUMN IF NOT EXISTS pro_profile_id   uuid REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS owner_profile_id uuid REFERENCES public.user_profiles(id) ON DELETE SET NULL;

-- owner_uid était NOT NULL sur certaines installs — on autorise NULL.
ALTER TABLE public.comptes_rendus ALTER COLUMN owner_uid DROP NOT NULL;

UPDATE public.comptes_rendus c
SET pro_profile_id = up.id
FROM public.user_profiles up
WHERE up.uid = c.pro_uid AND up.is_main = true AND c.pro_profile_id IS NULL;

UPDATE public.comptes_rendus c
SET owner_profile_id = up.id
FROM public.user_profiles up
WHERE up.uid = c.owner_uid AND up.profile_type = 'particulier' AND c.owner_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_comptes_rendus_pro_profile   ON public.comptes_rendus (pro_profile_id);
CREATE INDEX IF NOT EXISTS idx_comptes_rendus_owner_profile ON public.comptes_rendus (owner_profile_id);
CREATE INDEX IF NOT EXISTS idx_comptes_rendus_animal        ON public.comptes_rendus (animal_id);
