-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — correctif vague 29/N : policy résiduelle sur chenil_boxes /
-- enclos_chenil
-- ══════════════════════════════════════════════════════════════════════════
-- Test en conditions réelles (requête REST anonyme) : chenil_boxes et
-- enclos_chenil restaient lisibles anonymement après la vague 29/N. Cause
-- identique à l'incident vague 13/N (users) : la migration précédente
-- supprimait une policy par NOM DEVINÉ ("Owner chenil_boxes",
-- "Propriétaire enclos") au lieu de supprimer dynamiquement toute policy
-- existante — une policy résiduelle au nom différent (jamais vue dans les
-- fichiers de migration du dépôt, donc modifiée depuis ailleurs) est
-- restée active et, combinée en OR avec la nouvelle policy restrictive,
-- rendait cette dernière inefficace.
-- ══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['chenil_boxes','enclos_chenil']
  LOOP
    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;
  END LOOP;
END $$;

CREATE POLICY "chenil_boxes_owner_or_cogerant" ON chenil_boxes
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = association_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = chenil_boxes.association_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = association_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = chenil_boxes.association_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "enclos_chenil_owner_or_cogerant" ON enclos_chenil
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = enclos_chenil.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = enclos_chenil.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- Vérification — ne doit lister QUE les deux policies ci-dessus, une par table.
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('chenil_boxes','enclos_chenil')
ORDER BY tablename, cmd;
