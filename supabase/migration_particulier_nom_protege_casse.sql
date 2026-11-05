-- Profil particulier au nom de l'élevage : comparaison sans casse ni accents (05/11/2026).
-- migration_particulier_nom_protege.sql comparait au caractère près : « élevage des
-- neiges » (particulier) et « Élevage des neiges » (élevage renommé ensuite) n'étaient
-- pas reconnus. Réparation et garde-fou ignorent désormais majuscules, accents et
-- espaces autour. Anciennes valeurs dans sauv_rappels_sante_20261104. Idempotent.

BEGIN;

CREATE OR REPLACE FUNCTION public.pm_nom_compare(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT translate(lower(trim(COALESCE(p, ''))),
    'àâäáãåçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝ',
    'aaaaaaceeeeiiiinooooouuuuyyaaaaaaceeeeiiiinooooouuuuy');
$function$;

CREATE OR REPLACE FUNCTION public.pm_particulier_nom_protege()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.profile_type = 'particulier' AND NEW.nom IS DISTINCT FROM OLD.nom
     AND pm_nom_compare(NEW.nom) <> ''
     AND EXISTS (SELECT 1 FROM user_profiles e WHERE e.uid = NEW.uid AND e.id <> NEW.id
                  AND e.profile_type = 'eleveur' AND pm_nom_compare(e.nom) = pm_nom_compare(NEW.nom)) THEN
    NEW.nom := OLD.nom;
  END IF;
  RETURN NEW;
END;
$function$;

WITH touches AS (
  SELECT p.id, to_jsonb(p) AS ligne, trim(concat_ws(' ', NULLIF(trim(p.firstname), ''), NULLIF(trim(p.lastname), ''))) AS nouveau
    FROM user_profiles p
   WHERE p.profile_type = 'particulier'
     AND pm_nom_compare(p.nom) <> ''
     AND NULLIF(trim(concat_ws(' ', NULLIF(trim(p.firstname), ''), NULLIF(trim(p.lastname), ''))), '') IS NOT NULL
     AND EXISTS (SELECT 1 FROM user_profiles e WHERE e.uid = p.uid AND e.id <> p.id
                  AND e.profile_type = 'eleveur' AND pm_nom_compare(e.nom) = pm_nom_compare(p.nom))
), sauve AS (
  INSERT INTO public.sauv_rappels_sante_20261104 (source, ligne)
  SELECT 'user_profiles_particulier_nom', ligne FROM touches
)
UPDATE user_profiles p SET nom = t.nouveau FROM touches t WHERE p.id = t.id;

COMMIT;
