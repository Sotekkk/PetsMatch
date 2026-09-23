-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — correctif vague 19/N : accès propriétaire par ANIMAL, pas
-- par colonne owner_uid figée (mix de profil / co-propriétaires)
-- ══════════════════════════════════════════════════════════════════════════
-- La vague 19/N vérifiait `owner_uid = (auth.jwt() ->> 'sub')` sur
-- exercices_attribues / education_objectifs / education_attestations /
-- exercices_retours (via l'attribution parente) — une simple colonne
-- figée au moment de l'écriture. Deux problèmes :
--   1. Un animal peut avoir un CO-PROPRIÉTAIRE (animaux_proprietes,
--      co-propriétaires d'un animal, session précédente) qui a les mêmes
--      droits R/W complets sur l'animal, mais que owner_uid ne référence
--      jamais (une seule valeur possible sur cette colonne).
--   2. owner_uid est une valeur figée à l'écriture — si jamais mal
--      renseignée (mix de profil côté appli), la RLS ne peut plus la
--      corriger après coup, contrairement à une résolution dynamique par
--      animal_id.
-- Remplacé par la même résolution « propriétaire de l'animal » que
-- carnet de santé / repro / ostéo-morpho (vagues 14/16/17) : éleveur OU
-- propriétaire particulier OU cogérant actif OU co-propriétaire courant
-- (animaux_proprietes, date_fin IS NULL) — cohérent avec le reste du
-- projet, où tout se résout par la relation réelle à l'animal, jamais un
-- uid figé isolé.
--
-- ⚠️ À TESTER après exécution :
--   1. Le propriétaire (profil particulier) d'un animal voit toujours ses
--      objectifs, exercices attribués, attestations, retours d'exercice.
--   2. Un CO-PROPRIÉTAIRE de l'animal (ajouté via "Co-propriétaires")
--      voit désormais lui aussi ce suivi éducation, ce qui n'était pas le
--      cas avant ce correctif.
--   3. Muter les rappels d'un exercice fonctionne toujours pour le
--      propriétaire ET fonctionne maintenant pour un co-propriétaire.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_animal_owner_or_related(p_animal_id TEXT, p_uid TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT public.is_animal_owner_or_cogerant(p_animal_id, p_uid)
    OR EXISTS (
      SELECT 1 FROM animaux_proprietes p
      WHERE p.animal_id = p_animal_id
        AND p.uid_proprio = p_uid
        AND p.date_fin IS NULL
    );
$$;
GRANT EXECUTE ON FUNCTION public.is_animal_owner_or_related(TEXT, TEXT) TO anon, authenticated;

-- ── education_objectifs, education_attestations ────────────────────────────
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['education_objectifs','education_attestations']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;

    EXECUTE format($f$
      CREATE POLICY "%1$s_select" ON public.%1$I
        FOR SELECT USING (
          (auth.jwt() ->> 'sub') = pro_uid
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = %1$I.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
          OR public.is_animal_owner_or_related(%1$I.animal_id, (auth.jwt() ->> 'sub'))
        )
    $f$, t);

    EXECUTE format($f$
      CREATE POLICY "%1$s_write" ON public.%1$I
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

-- ── exercices_attribues (idem + propriétaire/co-propriétaire en écriture
--    pour le mute des rappels) ──────────────────────────────────────────
DROP POLICY IF EXISTS "exercices_attribues_select" ON exercices_attribues;
DROP POLICY IF EXISTS "exercices_attribues_update" ON exercices_attribues;

CREATE POLICY "exercices_attribues_select" ON exercices_attribues
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = exercices_attribues.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR public.is_animal_owner_or_related(exercices_attribues.animal_id, (auth.jwt() ->> 'sub'))
  );

CREATE POLICY "exercices_attribues_update" ON exercices_attribues
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = exercices_attribues.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR public.is_animal_owner_or_related(exercices_attribues.animal_id, (auth.jwt() ->> 'sub'))
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = exercices_attribues.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR public.is_animal_owner_or_related(exercices_attribues.animal_id, (auth.jwt() ->> 'sub'))
  );

-- ── exercices_retours (rattaché via attribution_id → exercices_attribues) ─
DROP POLICY IF EXISTS "exercices_retours_related" ON exercices_retours;

CREATE POLICY "exercices_retours_related" ON exercices_retours
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM exercices_attribues ea
      WHERE ea.id = exercices_retours.attribution_id
        AND (
          ea.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = ea.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
          OR public.is_animal_owner_or_related(ea.animal_id, (auth.jwt() ->> 'sub'))
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM exercices_attribues ea
      WHERE ea.id = exercices_retours.attribution_id
        AND (
          ea.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = ea.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
          OR public.is_animal_owner_or_related(ea.animal_id, (auth.jwt() ->> 'sub'))
        )
    )
  );

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('exercices_attribues','exercices_retours','education_objectifs','education_attestations')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue : relancer simplement
-- migration_rls_tighten_education.sql (vague 19/N), qui recrée les
-- policies précédentes (owner_uid figé) sur ces 4 tables.
-- ══════════════════════════════════════════════════════════════════════════
-- DROP FUNCTION IF EXISTS public.is_animal_owner_or_related(TEXT, TEXT);
