-- Profil particulier renommé avec le nom de l'élevage du même compte (05/11/2026).
-- L'écran d'édition de l'élevage de l'appli écrivait sur le profil PRINCIPAL du
-- compte (is_main) au lieu du profil élevage : avec un particulier en principal,
-- son « nom » prenait celui de l'élevage (corrigé dans profil_eleveur_edit.dart).
--   • Réparation : particulier dont le nom est celui d'un élevage du même compte →
--     prénom + nom. Anciennes valeurs dans sauv_rappels_sante_20261104.
--   • Garde-fou pour les anciennes versions de l'appli : un particulier ne peut plus
--     recevoir le nom d'un élevage de son compte.
-- Les autres champs écrasés (description, adresse, téléphone) n'ont pas de copie :
-- à ressaisir par la personne. Idempotent.

BEGIN;

CREATE OR REPLACE FUNCTION public.pm_particulier_nom_protege()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.profile_type = 'particulier' AND NEW.nom IS DISTINCT FROM OLD.nom
     AND EXISTS (SELECT 1 FROM user_profiles e WHERE e.uid = NEW.uid AND e.id <> NEW.id
                  AND e.profile_type = 'eleveur' AND e.nom = NEW.nom) THEN
    NEW.nom := OLD.nom;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_particulier_nom_protege ON public.user_profiles;
CREATE TRIGGER trg_particulier_nom_protege BEFORE UPDATE OF nom ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.pm_particulier_nom_protege();

WITH touches AS (
  SELECT p.id, to_jsonb(p) AS ligne, trim(concat_ws(' ', NULLIF(trim(p.firstname), ''), NULLIF(trim(p.lastname), ''))) AS nouveau
    FROM user_profiles p
   WHERE p.profile_type = 'particulier'
     AND NULLIF(trim(COALESCE(p.nom, '')), '') IS NOT NULL
     AND NULLIF(trim(concat_ws(' ', NULLIF(trim(p.firstname), ''), NULLIF(trim(p.lastname), ''))), '') IS NOT NULL
     AND EXISTS (SELECT 1 FROM user_profiles e WHERE e.uid = p.uid AND e.id <> p.id AND e.profile_type = 'eleveur' AND e.nom = p.nom)
), sauve AS (
  INSERT INTO public.sauv_rappels_sante_20261104 (source, ligne)
  SELECT 'user_profiles_particulier_nom', ligne FROM touches
)
UPDATE user_profiles p SET nom = t.nouveau FROM touches t WHERE p.id = t.id;

COMMIT;
