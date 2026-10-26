-- animal_access : un co-propriétaire (animaux_proprietes, principal ou
-- secondaire) peut partager la fiche avec un pro, comme le propriétaire.
-- Avant : seuls animaux.uid_eleveur / uid_proprietaire / cogérants étaient
-- reconnus → le partage du carnet à la prise de RDV échouait en silence pour
-- un co-propriétaire (ex. Venicia, 26/10 : aucun accès créé, le véto ne
-- voyait aucun vaccin et le site affichait « pas d'accès »).
-- Le côté pro (profil du pro connecté) est inchangé.

DROP POLICY IF EXISTS animal_access_related_select ON public.animal_access;
CREATE POLICY animal_access_related_select ON public.animal_access
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.user_profiles up
            WHERE up.id = animal_access.pro_profile_id AND up.uid = (auth.jwt() ->> 'sub'))
    OR public.is_animal_owner_or_cogerant(animal_id, (auth.jwt() ->> 'sub'))
  );

DROP POLICY IF EXISTS animal_access_related_insert ON public.animal_access;
CREATE POLICY animal_access_related_insert ON public.animal_access
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.user_profiles up
            WHERE up.id = animal_access.pro_profile_id AND up.uid = (auth.jwt() ->> 'sub'))
    OR public.is_animal_owner_or_cogerant(animal_id, (auth.jwt() ->> 'sub'))
  );

DROP POLICY IF EXISTS animal_access_related_update ON public.animal_access;
CREATE POLICY animal_access_related_update ON public.animal_access
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM public.user_profiles up
            WHERE up.id = animal_access.pro_profile_id AND up.uid = (auth.jwt() ->> 'sub'))
    OR public.is_animal_owner_or_cogerant(animal_id, (auth.jwt() ->> 'sub'))
  );

DROP POLICY IF EXISTS animal_access_related_delete ON public.animal_access;
CREATE POLICY animal_access_related_delete ON public.animal_access
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM public.user_profiles up
            WHERE up.id = animal_access.pro_profile_id AND up.uid = (auth.jwt() ->> 'sub'))
    OR public.is_animal_owner_or_cogerant(animal_id, (auth.jwt() ->> 'sub'))
  );
