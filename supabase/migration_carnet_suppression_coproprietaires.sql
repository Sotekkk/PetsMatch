-- ════════════════════════════════════════════════════════════════════════
-- Carnet de santé : un co-propriétaire peut supprimer une entrée.
--
-- La policy de suppression (migration_rls_tighten_carnet_sante.sql) ne
-- reconnaissait que uid_eleveur / uid_proprietaire de la fiche (et les
-- cogérants) : un co-propriétaire (animaux_proprietes, actif) voyait le
-- bouton « Supprimer », mais la base refusait sans message — « on ne peut
-- plus supprimer » (ex. traitements de VENICIA). Les co-propriétaires ont
-- les mêmes droits que le principal sur le carnet (lecture / écriture).
-- Seule la suppression change. Idempotent.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['vaccinations','visites','traitements','vermifuges','antiparasitaires','allergies','poids','chirurgies']
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_health_delete', t);
    EXECUTE format($f$
      CREATE POLICY "%1$s_health_delete" ON public.%1$I
        FOR DELETE USING (
          EXISTS (
            SELECT 1 FROM animaux a
            WHERE a.id = %1$I.animal_id
              AND (
                a.uid_eleveur = (auth.jwt() ->> 'sub') OR a.uid_proprietaire = (auth.jwt() ->> 'sub')
                OR EXISTS (
                  SELECT 1 FROM elevage_cogerants c
                  WHERE c.uid_gerant = a.uid_eleveur
                    AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
                )
                -- Propriétaires actifs (principal et co-propriétaires).
                OR EXISTS (
                  SELECT 1 FROM animaux_proprietes p
                  WHERE p.animal_id = a.id AND p.uid_proprio = (auth.jwt() ->> 'sub')
                    AND p.date_fin IS NULL AND coalesce(p.statut, 'actif') = 'actif'
                )
              )
          )
        )
    $f$, t);
  END LOOP;
END $$;

COMMIT;
