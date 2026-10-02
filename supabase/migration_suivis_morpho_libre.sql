-- ════════════════════════════════════════════════════════════════════════
-- Suivi morpho « libre » (client occasionnel, animal sans fiche dans
-- l'appli : Suivis morpho → Nouveau suivi → client sans fiche) :
-- animal_id NULL → can_access_animal_morpho(NULL, …) = faux → création
-- refusée par la RLS, et l'auteur ne pouvait de toute façon pas relire son
-- suivi (la lecture ne passait que par l'animal).
-- - création : l'auteur lui-même, avec accès en écriture à l'animal OU sans
--   animal (saisie libre) ;
-- - lecture : accès à l'animal OU auteur du suivi.
-- (Éléments rattachés : can_access_suivi_morpho inclut déjà l'auteur.)
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

DROP POLICY IF EXISTS suivis_morpho_insert ON public.suivis_morpho;
CREATE POLICY suivis_morpho_insert ON public.suivis_morpho
  FOR INSERT TO anon, authenticated
  WITH CHECK (
    uid_auteur = (auth.jwt() ->> 'sub')
    AND (animal_id IS NULL
         OR public.can_access_animal_morpho(animal_id, (auth.jwt() ->> 'sub'), true))
  );

DROP POLICY IF EXISTS suivis_morpho_select ON public.suivis_morpho;
CREATE POLICY suivis_morpho_select ON public.suivis_morpho
  FOR SELECT TO anon, authenticated
  USING (
    uid_auteur = (auth.jwt() ->> 'sub')
    OR public.can_access_animal_morpho(animal_id, (auth.jwt() ->> 'sub'), false)
  );

COMMIT;
