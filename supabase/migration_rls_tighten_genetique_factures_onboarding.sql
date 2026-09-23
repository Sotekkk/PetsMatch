-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 31/N : tests_genetiques, taxi_factures,
--   photographe_factures, onboarding_progress
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- tests_genetiques : contrairement au carnet de santé, ces résultats sont
-- volontairement affichés publiquement (fiche reproducteur publique,
-- annonce — transparence génétique reconnue dans l'élevage). Lecture
-- publique conservée, écriture verrouillée au propriétaire de
-- l'animal/cogérant (résolution par animal_id, comme carnet de santé/
-- repro/ostéo-morpho — jamais une colonne uid figée).
--
-- taxi_factures, photographe_factures : USING(true), jamais lues côté
-- client (vérifié, comme toilettage_factures/pension_entrees) — réservé
-- pro/cogérant.
--
-- onboarding_progress : USING(true) — état d'avancement de l'onboarding
-- d'un profil, personnel. Réservé au propriétaire du profil concerné.
--
-- ⚠️ À TESTER après exécution :
--   1. Les tests génétiques restent visibles sur la fiche reproducteur
--      publique et l'annonce ; les ajouter/modifier fonctionne pour
--      l'éleveur/cogérant.
--   2. La facturation taxi animalier / photographe fonctionne normalement
--      pour son pro/cogérant.
--   3. Le bandeau/onboarding (étapes complétées, "ignorer") continue de
--      fonctionner pour chaque profil.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── tests_genetiques (lecture publique, écriture par animal_id) ──────────
DROP POLICY IF EXISTS "tg_all" ON tests_genetiques;

CREATE POLICY "tests_genetiques_select" ON tests_genetiques FOR SELECT USING (true);

CREATE POLICY "tests_genetiques_write" ON tests_genetiques
  FOR ALL USING (public.is_animal_owner_or_related(tests_genetiques.animal_id, (auth.jwt() ->> 'sub')))
  WITH CHECK (public.is_animal_owner_or_related(tests_genetiques.animal_id, (auth.jwt() ->> 'sub')));

-- ── taxi_factures, photographe_factures (pro/cogérant uniquement) ─────────
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['taxi_factures','photographe_factures']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;

    EXECUTE format($f$
      CREATE POLICY "%1$s_pro_or_cogerant" ON public.%1$I
        FOR ALL USING (
          (auth.jwt() ->> 'sub') = pro_uid
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = %1$I.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
        WITH CHECK (
          (auth.jwt() ->> 'sub') = pro_uid
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = %1$I.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    $f$, t);
  END LOOP;
END $$;

-- ── onboarding_progress (propriétaire du profil concerné) ─────────────────
DROP POLICY IF EXISTS onboarding_progress_all ON onboarding_progress;
CREATE POLICY "onboarding_progress_owner" ON onboarding_progress
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM user_profiles up
      WHERE up.id = onboarding_progress.profile_id AND up.uid = (auth.jwt() ->> 'sub')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles up
      WHERE up.id = onboarding_progress.profile_id AND up.uid = (auth.jwt() ->> 'sub')
    )
  );

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('tests_genetiques','taxi_factures','photographe_factures','onboarding_progress')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('tests_genetiques','taxi_factures','photographe_factures','onboarding_progress')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- CREATE POLICY "tg_all" ON tests_genetiques FOR ALL USING (true) WITH CHECK (true);
-- CREATE POLICY "taxi_factures_all" ON taxi_factures FOR ALL USING (true);
-- CREATE POLICY "photographe_factures_all" ON photographe_factures FOR ALL USING (true);
-- CREATE POLICY onboarding_progress_all ON onboarding_progress USING (true) WITH CHECK (true);
