-- alimentations : lecture aussi pour le professionnel (pension, pet-sitter…)
-- à qui le propriétaire a accordé un accès actif à la fiche avec la permission
-- « alimentation » (animal_access.permissions contient read_alimentation) —
-- avant, seule une pension ayant déjà un séjour enregistré pouvait la lire
-- (fiche pensionnaire vide avant l'admission). Écriture inchangée
-- (propriétaire / co-propriétaires). Idempotent.
DROP POLICY IF EXISTS "alimentations_select" ON public.alimentations;
CREATE POLICY "alimentations_select" ON public.alimentations
  FOR SELECT USING (
    public.is_animal_owner_or_related(animal_id, (auth.jwt() ->> 'sub'))
    OR EXISTS (
      SELECT 1 FROM pension_entrees pe
      WHERE pe.animal_id = alimentations.animal_id
        AND (
          pe.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = pe.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    )
    OR EXISTS (
      SELECT 1 FROM animal_access aa
      JOIN user_profiles up ON up.id = aa.pro_profile_id
      WHERE aa.animal_id = alimentations.animal_id
        AND aa.statut IN ('active', 'active_write')
        AND 'read_alimentation' = ANY (aa.permissions)
        AND (
          up.uid = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = up.uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    )
  );

NOTIFY pgrst, 'reload schema';
