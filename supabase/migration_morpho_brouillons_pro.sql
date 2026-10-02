-- ════════════════════════════════════════════════════════════════════════
-- Suivis morpho d'un pro : invisibles du propriétaire (et des autres pros)
-- tant qu'ils ne sont pas ENVOYÉS (notifie_a). L'écran du pro annonce « Le
-- client ne voit pas encore ce bilan », mais la RLS le montrait déjà à
-- tous ceux qui ont accès à l'animal.
-- Lecture d'un suivi :
--   • son auteur, toujours ;
--   • les autres (propriétaire, co-propriétaires, pros ayant accès) : si le
--     suivi n'est pas un bilan pro (saisi par le propriétaire), ou s'il a
--     été envoyé.
-- Même règle pour les éléments rattachés (photos, vidéos, points…), via
-- can_access_suivi_morpho en lecture. L'écriture est inchangée.
-- (Même compte propriétaire + pro : filtrage par profil côté appli.)
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

DROP POLICY IF EXISTS suivis_morpho_select ON public.suivis_morpho;
CREATE POLICY suivis_morpho_select ON public.suivis_morpho
  FOR SELECT TO anon, authenticated
  USING (
    uid_auteur = (auth.jwt() ->> 'sub')
    OR (public.can_access_animal_morpho(animal_id, (auth.jwt() ->> 'sub'), false)
        AND (coalesce(source, '') <> 'professionnel' OR notifie_a IS NOT NULL))
  );

CREATE OR REPLACE FUNCTION public.can_access_suivi_morpho(p_suivi_id uuid, p_uid text, p_require_write boolean DEFAULT false)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM suivis_morpho sm
    WHERE sm.id = p_suivi_id
      AND (
        sm.uid_auteur = p_uid
        OR (public.can_access_animal_morpho(sm.animal_id, p_uid, p_require_write)
            AND (p_require_write
                 OR coalesce(sm.source, '') <> 'professionnel'
                 OR sm.notifie_a IS NOT NULL))
      )
  );
$function$;

COMMIT;
