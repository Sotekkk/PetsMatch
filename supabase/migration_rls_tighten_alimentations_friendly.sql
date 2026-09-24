-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 42/N : alimentations, animal_friendly_lieux
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- alimentations (calcul de ration par animal) : résolution par animal_id
-- (co-propriétaires inclus, is_animal_owner_or_related — cf. mémoire RLS
-- liée à un animal), PLUS lecture pour le pro pension ayant une entrée
-- active pour cet animal (animal_fiche_pension_page.dart, lecture seule
-- confirmée — aucune écriture pension trouvée côté pro).
--
-- animal_friendly_lieux (carte contributive de lieux pet-friendly,
-- friendly_map_page.dart — distincte du module `petfriendly_places`
-- modéré) : lecture publique, contribution par tout utilisateur connecté
-- (ajout_par_uid), modification/suppression réservées au contributeur.
--
-- ⚠️ À TESTER après exécution :
--   1. Le calcul de ration (fiche animal éleveur/particulier) fonctionne
--      pour le propriétaire ET reste visible en lecture pour la pension
--      qui héberge l'animal.
--   2. La carte des lieux pet-friendly contributifs reste publique ;
--      ajouter un lieu fonctionne pour tout utilisateur connecté.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── alimentations ───────────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE alimentations ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'alimentations'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.alimentations', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "alimentations_select" ON alimentations
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
  );
CREATE POLICY "alimentations_write" ON alimentations
  FOR ALL USING (public.is_animal_owner_or_related(animal_id, (auth.jwt() ->> 'sub')))
  WITH CHECK (public.is_animal_owner_or_related(animal_id, (auth.jwt() ->> 'sub')));

-- ── animal_friendly_lieux (carte contributive publique) ───────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE animal_friendly_lieux ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'animal_friendly_lieux'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.animal_friendly_lieux', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "animal_friendly_lieux_select" ON animal_friendly_lieux FOR SELECT USING (true);
CREATE POLICY "animal_friendly_lieux_insert" ON animal_friendly_lieux
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = ajout_par_uid);
CREATE POLICY "animal_friendly_lieux_update" ON animal_friendly_lieux
  FOR UPDATE USING ((auth.jwt() ->> 'sub') = ajout_par_uid) WITH CHECK ((auth.jwt() ->> 'sub') = ajout_par_uid);
CREATE POLICY "animal_friendly_lieux_delete" ON animal_friendly_lieux
  FOR DELETE USING ((auth.jwt() ->> 'sub') = ajout_par_uid);

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('alimentations','animal_friendly_lieux')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('alimentations','animal_friendly_lieux')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- ALTER TABLE alimentations DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE animal_friendly_lieux DISABLE ROW LEVEL SECURITY;
