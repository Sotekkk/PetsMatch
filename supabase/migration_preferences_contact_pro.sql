-- Préférences de contact d'un profil professionnel (30/10/2026) : le pro
-- choisit, à la création et dans l'édition de son profil, s'il accepte
--  • contact_messages : les messages PetsMatch (bouton « Message » des fiches) ;
--  • contact_email    : d'être contacté par e-mail (e-mail affiché sur ses fiches).
-- Par défaut : oui (comportement actuel). Lues par pm_preferences_contact
-- (fiches publiques, ContactModal / showContactSheet), sans toucher à la vue
-- user_profiles_complet.

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS contact_messages boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS contact_email boolean NOT NULL DEFAULT true;

-- Lecture colonne par colonne (migration_donnees_perso_revoke.sql) : non sensibles.
GRANT SELECT (contact_messages, contact_email) ON public.user_profiles TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.pm_preferences_contact(p_profile uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(
    (SELECT jsonb_build_object('messages', up.contact_messages, 'email', up.contact_email)
       FROM user_profiles up WHERE up.id = p_profile),
    jsonb_build_object('messages', true, 'email', true));
$$;
GRANT EXECUTE ON FUNCTION public.pm_preferences_contact(uuid) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
