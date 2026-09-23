-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 17/N : ostéopathie / suivi morpho
--   points_osteo, seances_osteo, suivis_morpho (+ 6 sous-tables :
--   suivis_morpho_photos, _videos, _zones, _observations, _mouvements,
--   _points)
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- Ces 9 tables avaient déjà `ENABLE ROW LEVEL SECURITY`, mais avec des
-- policies nommément permissives ("..._anon", "Select ..." etc.,
-- `USING (true)`) — même situation que toutes les vagues précédentes,
-- juste avec RLS déjà « activée » en apparence.
--
-- Modèle retenu :
--   - Propriétaire de l'animal / cogérant actif : accès complet, comme
--     toujours.
--   - Le pro AUTEUR de l'entrée (pro_uid pour points_osteo/seances_osteo,
--     uid_auteur pour suivis_morpho — ce peut aussi être le propriétaire
--     lui-même qui fait son propre suivi) : lecture/modification/
--     suppression de SES entrées.
--   - Tout pro avec un accès accordé (animal_access, statut active/
--     active_write, via has_animal_access déjà créée en vague 5) : lecture
--     toujours ; création réservée à active_write, ET seulement en son
--     propre nom (pro_uid/uid_auteur doit être lui, pas un tiers).
--   - Les 6 sous-tables (photos/vidéos/zones/observations/mouvements/
--     points d'un suivi_morpho) héritent des droits du suivi parent via
--     suivi_id — jamais de colonne animal_id à elles.
--
-- ⚠️ À TESTER après exécution :
--   1. Le canvas ostéo (points + séances) et le suivi morpho (bilans,
--      photos, vidéos, zones, observations, mouvements) s'affichent
--      normalement pour l'éleveur/cogérant ET pour le pro qui les a créés.
--   2. Créer une séance ostéo / un suivi morpho, y ajouter un point/une
--      photo/une observation fonctionne toujours.
--   3. Un vétérinaire/ostéo avec un accès "écriture" accordé peut créer
--      ses propres entrées ; un accès "lecture seule" ne peut plus écrire.
--   4. Un profil PUBLIC (reproducteur_public) ne doit PAS exposer son
--      suivi ostéo/morpho à un visiteur non connecté.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_animal_owner_or_cogerant(p_animal_id TEXT, p_uid TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM animaux a
    WHERE a.id = p_animal_id
      AND (
        a.uid_eleveur = p_uid OR a.uid_proprietaire = p_uid
        OR EXISTS (
          SELECT 1 FROM elevage_cogerants c
          WHERE c.uid_gerant = a.uid_eleveur
            AND c.uid_cogerant = p_uid AND c.statut = 'actif' AND c.date_fin IS NULL
        )
      )
  );
$$;
GRANT EXECUTE ON FUNCTION public.is_animal_owner_or_cogerant(TEXT, TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.can_access_animal_morpho(p_animal_id TEXT, p_uid TEXT, p_require_write BOOLEAN DEFAULT false)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT public.is_animal_owner_or_cogerant(p_animal_id, p_uid)
    OR public.has_animal_access(p_animal_id, p_uid, p_require_write);
$$;
GRANT EXECUTE ON FUNCTION public.can_access_animal_morpho(TEXT, TEXT, BOOLEAN) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.can_access_suivi_morpho(p_suivi_id UUID, p_uid TEXT, p_require_write BOOLEAN DEFAULT false)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM suivis_morpho sm
    WHERE sm.id = p_suivi_id
      AND (
        public.can_access_animal_morpho(sm.animal_id, p_uid, p_require_write)
        OR sm.uid_auteur = p_uid
      )
  );
$$;
GRANT EXECUTE ON FUNCTION public.can_access_suivi_morpho(UUID, TEXT, BOOLEAN) TO anon, authenticated;

-- ── points_osteo, seances_osteo (animal_id direct, colonne pro_uid) ───────
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['points_osteo','seances_osteo']
  LOOP
    -- Certaines de ces tables peuvent ne pas exister si leur migration de
    -- création n'a jamais été exécutée — on les ignore plutôt que d'échouer.
    IF to_regclass('public.' || t) IS NULL THEN
      CONTINUE;
    END IF;

    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);

    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;

    EXECUTE format($f$
      CREATE POLICY "%1$s_morpho_select" ON public.%1$I
        FOR SELECT USING (public.can_access_animal_morpho(animal_id, (auth.jwt() ->> 'sub'), false))
    $f$, t);

    EXECUTE format($f$
      CREATE POLICY "%1$s_morpho_insert" ON public.%1$I
        FOR INSERT WITH CHECK (
          public.can_access_animal_morpho(animal_id, (auth.jwt() ->> 'sub'), true)
          AND pro_uid = (auth.jwt() ->> 'sub')
        )
    $f$, t);

    EXECUTE format($f$
      CREATE POLICY "%1$s_morpho_update" ON public.%1$I
        FOR UPDATE USING (
          public.is_animal_owner_or_cogerant(animal_id, (auth.jwt() ->> 'sub'))
          OR pro_uid = (auth.jwt() ->> 'sub')
        )
        WITH CHECK (
          public.is_animal_owner_or_cogerant(animal_id, (auth.jwt() ->> 'sub'))
          OR pro_uid = (auth.jwt() ->> 'sub')
        )
    $f$, t);

    EXECUTE format($f$
      CREATE POLICY "%1$s_morpho_delete" ON public.%1$I
        FOR DELETE USING (
          public.is_animal_owner_or_cogerant(animal_id, (auth.jwt() ->> 'sub'))
          OR pro_uid = (auth.jwt() ->> 'sub')
        )
    $f$, t);
  END LOOP;
END $$;

-- ── suivis_morpho (animal_id direct, colonne uid_auteur) ──────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  IF to_regclass('public.suivis_morpho') IS NULL THEN
    RETURN;
  END IF;

  ALTER TABLE suivis_morpho ENABLE ROW LEVEL SECURITY;

  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'suivis_morpho'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.suivis_morpho', pol.policyname);
  END LOOP;

  EXECUTE $p$
    CREATE POLICY "suivis_morpho_select" ON suivis_morpho
      FOR SELECT USING (public.can_access_animal_morpho(animal_id, (auth.jwt() ->> 'sub'), false))
  $p$;

  EXECUTE $p$
    CREATE POLICY "suivis_morpho_insert" ON suivis_morpho
      FOR INSERT WITH CHECK (
        public.can_access_animal_morpho(animal_id, (auth.jwt() ->> 'sub'), true)
        AND uid_auteur = (auth.jwt() ->> 'sub')
      )
  $p$;

  EXECUTE $p$
    CREATE POLICY "suivis_morpho_update" ON suivis_morpho
      FOR UPDATE USING (
        public.is_animal_owner_or_cogerant(animal_id, (auth.jwt() ->> 'sub'))
        OR uid_auteur = (auth.jwt() ->> 'sub')
      )
      WITH CHECK (
        public.is_animal_owner_or_cogerant(animal_id, (auth.jwt() ->> 'sub'))
        OR uid_auteur = (auth.jwt() ->> 'sub')
      )
  $p$;

  EXECUTE $p$
    CREATE POLICY "suivis_morpho_delete" ON suivis_morpho
      FOR DELETE USING (
        public.is_animal_owner_or_cogerant(animal_id, (auth.jwt() ->> 'sub'))
        OR uid_auteur = (auth.jwt() ->> 'sub')
      )
  $p$;
END $$;

-- ── Sous-tables suivis_morpho_* (rattachées via suivi_id) ─────────────────
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['suivis_morpho_photos','suivis_morpho_videos','suivis_morpho_zones','suivis_morpho_observations','suivis_morpho_mouvements','suivis_morpho_points']
  LOOP
    -- Certaines de ces sous-tables peuvent ne pas exister si leur migration
    -- de création n'a jamais été exécutée — on les ignore plutôt que
    -- d'échouer (constaté en pratique pour suivis_morpho_zones).
    IF to_regclass('public.' || t) IS NULL THEN
      CONTINUE;
    END IF;

    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);

    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;

    EXECUTE format($f$
      CREATE POLICY "%1$s_related_select" ON public.%1$I
        FOR SELECT USING (public.can_access_suivi_morpho(suivi_id, (auth.jwt() ->> 'sub'), false))
    $f$, t);

    EXECUTE format($f$
      CREATE POLICY "%1$s_related_insert" ON public.%1$I
        FOR INSERT WITH CHECK (public.can_access_suivi_morpho(suivi_id, (auth.jwt() ->> 'sub'), true))
    $f$, t);

    EXECUTE format($f$
      CREATE POLICY "%1$s_related_update" ON public.%1$I
        FOR UPDATE USING (public.can_access_suivi_morpho(suivi_id, (auth.jwt() ->> 'sub'), true))
        WITH CHECK (public.can_access_suivi_morpho(suivi_id, (auth.jwt() ->> 'sub'), true))
    $f$, t);

    EXECUTE format($f$
      CREATE POLICY "%1$s_related_delete" ON public.%1$I
        FOR DELETE USING (public.can_access_suivi_morpho(suivi_id, (auth.jwt() ->> 'sub'), true))
    $f$, t);
  END LOOP;
END $$;

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('points_osteo','seances_osteo','suivis_morpho','suivis_morpho_photos','suivis_morpho_videos','suivis_morpho_zones','suivis_morpho_observations','suivis_morpho_mouvements','suivis_morpho_points')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('points_osteo','seances_osteo','suivis_morpho','suivis_morpho_photos','suivis_morpho_videos','suivis_morpho_zones','suivis_morpho_observations','suivis_morpho_mouvements','suivis_morpho_points')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- CREATE POLICY "Select points_osteo" ON points_osteo FOR SELECT USING (true);
-- CREATE POLICY "Insert points_osteo" ON points_osteo FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND length(pro_uid) > 0);
-- CREATE POLICY "Update points_osteo" ON points_osteo FOR UPDATE USING (true);
-- CREATE POLICY "Delete points_osteo" ON points_osteo FOR DELETE USING (true);
-- CREATE POLICY "Select seances_osteo" ON seances_osteo FOR SELECT USING (true);
-- CREATE POLICY "Insert seances_osteo" ON seances_osteo FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND length(pro_uid) > 0);
-- CREATE POLICY "Update seances_osteo" ON seances_osteo FOR UPDATE USING (true);
-- CREATE POLICY "Delete seances_osteo" ON seances_osteo FOR DELETE USING (true);
-- CREATE POLICY "suivis_morpho_anon" ON suivis_morpho FOR ALL USING (true) WITH CHECK (true);
-- CREATE POLICY "suivis_morpho_photos_anon" ON suivis_morpho_photos FOR ALL USING (true) WITH CHECK (true);
-- CREATE POLICY "suivis_morpho_videos_anon" ON suivis_morpho_videos FOR ALL USING (true) WITH CHECK (true);
-- CREATE POLICY "suivis_morpho_zones_anon" ON suivis_morpho_zones FOR ALL USING (true) WITH CHECK (true);
-- CREATE POLICY "suivis_morpho_observations_anon" ON suivis_morpho_observations FOR ALL USING (true) WITH CHECK (true);
-- CREATE POLICY "suivis_morpho_mouvements_anon" ON suivis_morpho_mouvements FOR ALL USING (true) WITH CHECK (true);
-- CREATE POLICY "suivis_morpho_points_anon" ON suivis_morpho_points FOR ALL USING (true) WITH CHECK (true);
-- DROP FUNCTION IF EXISTS public.can_access_suivi_morpho(UUID, TEXT, BOOLEAN);
-- DROP FUNCTION IF EXISTS public.can_access_animal_morpho(TEXT, TEXT, BOOLEAN);
-- DROP FUNCTION IF EXISTS public.is_animal_owner_or_cogerant(TEXT, TEXT);
