-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 41/N : evenements, evenements_inscrits, creneaux_pro,
--   zones_intervention, prestations_education, prestations_photographe,
--   prestations_toilettage, credit_packs, radios, signalements_alertes,
--   tache_commentaires, bebes_portee
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- evenements / evenements_inscrits : mur communautaire public (comme
-- promenades, vague 35/N — pas d'accepter/refuser ici, simple inscription/
-- désinscription self). Lecture publique, écriture créateur/inscrit lui-même.
--
-- creneaux_pro / zones_intervention / prestations_education/photographe/
-- toilettage : catalogues/plannings publics du pro (recherche par lieu,
-- réservation d'un créneau) — lecture publique, écriture pro/cogérant.
--
-- credit_packs : catalogue d'achat de crédits, lecture publique, écriture
-- jamais côté client (toujours via l'admin) — verrouillé à l'admin.
--
-- radios (imagerie médicale liée à un animal) : même modèle que le carnet
-- de santé — réutilise can_access_animal_health().
--
-- tache_commentaires : rattaché à taches_elevage (vague 7/N) — mêmes
-- droits que la tâche parente (propriétaire/cogérant/employé assigné).
--
-- signalements_alertes : vue agrégée (pas de colonne id, comptage de
-- signalements) — verrouillée en lecture à l'admin si c'est une vraie
-- table ; si c'est une vue, ses privilèges de base sont révoqués à
-- anon/authenticated (elle s'appuie de toute façon sur `signalements`,
-- déjà verrouillée, vague 25/N).
--
-- bebes_portee : AUCUNE référence dans le code actuel — verrouillé par
-- sécurité (uid_eleveur), sans impact fonctionnel connu.
--
-- ⚠️ À TESTER après exécution :
--   1. Le fil des événements communautaires reste public ; créer un
--      événement, s'y inscrire/désinscrire fonctionnent.
--   2. La prise de RDV (créneaux, prestations éducation/photographe/
--      toilettage, zone d'intervention) reste visible publiquement et
--      modifiable par le pro/cogérant.
--   3. L'achat de crédits (packs) reste visible.
--   4. Les radios d'un animal restent visibles pour son propriétaire/véto.
--   5. Les commentaires d'une tâche s'affichent pour l'éleveur/cogérant/
--      employé assigné.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── evenements ──────────────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE evenements ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'evenements'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.evenements', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "evenements_select" ON evenements FOR SELECT USING (true);
CREATE POLICY "evenements_write" ON evenements
  FOR ALL USING ((auth.jwt() ->> 'sub') = createur_uid) WITH CHECK ((auth.jwt() ->> 'sub') = createur_uid);

-- ── evenements_inscrits ─────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE evenements_inscrits ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'evenements_inscrits'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.evenements_inscrits', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "evenements_inscrits_select" ON evenements_inscrits FOR SELECT USING (true);
CREATE POLICY "evenements_inscrits_write" ON evenements_inscrits
  FOR ALL USING ((auth.jwt() ->> 'sub') = user_uid) WITH CHECK ((auth.jwt() ->> 'sub') = user_uid);

-- ── creneaux_pro / zones_intervention / prestations_* (publics, écriture pro/cogérant) ──
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['creneaux_pro','zones_intervention','prestations_education','prestations_photographe','prestations_toilettage']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;
    EXECUTE format($f$ CREATE POLICY "%1$s_select" ON public.%1$I FOR SELECT USING (true) $f$, t);
    EXECUTE format($f$
      CREATE POLICY "%1$s_write" ON public.%1$I
        FOR ALL USING (
          (auth.jwt() ->> 'sub') = pro_uid
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = %1$I.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
        WITH CHECK (
          (auth.jwt() ->> 'sub') = pro_uid
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = %1$I.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    $f$, t);
  END LOOP;
END $$;

-- ── credit_packs (catalogue public, écriture admin) ────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE credit_packs ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'credit_packs'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.credit_packs', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "credit_packs_select" ON credit_packs FOR SELECT USING (true);
CREATE POLICY "credit_packs_write" ON credit_packs
  FOR ALL USING (public.is_admin_uid((auth.jwt() ->> 'sub')))
  WITH CHECK (public.is_admin_uid((auth.jwt() ->> 'sub')));

-- ── radios (imagerie médicale, même modèle que le carnet de santé) ────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE radios ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'radios'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.radios', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "radios_select" ON radios
  FOR SELECT USING (public.can_access_animal_health(animal_id, (auth.jwt() ->> 'sub'), false));
CREATE POLICY "radios_write" ON radios
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = vet_id
    OR public.can_access_animal_health(animal_id, (auth.jwt() ->> 'sub'), true)
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = vet_id
    OR public.can_access_animal_health(animal_id, (auth.jwt() ->> 'sub'), true)
  );

-- ── tache_commentaires (droits de la tâche parente) ────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE tache_commentaires ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'tache_commentaires'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.tache_commentaires', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "tache_commentaires_select" ON tache_commentaires
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM taches_elevage t
      WHERE t.id = tache_commentaires.tache_id
        AND (
          t.uid_eleveur = (auth.jwt() ->> 'sub')
          OR t.assigne_a = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = t.uid_eleveur AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    )
  );
CREATE POLICY "tache_commentaires_insert" ON tache_commentaires
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_auteur
    AND EXISTS (
      SELECT 1 FROM taches_elevage t
      WHERE t.id = tache_commentaires.tache_id
        AND (
          t.uid_eleveur = (auth.jwt() ->> 'sub')
          OR t.assigne_a = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = t.uid_eleveur AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    )
  );
CREATE POLICY "tache_commentaires_delete" ON tache_commentaires
  FOR DELETE USING ((auth.jwt() ->> 'sub') = uid_auteur);

-- ── signalements_alertes (table ou vue agrégée — verrouillée si table) ────
DO $$
DECLARE pol RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'signalements_alertes') THEN
    -- C'est une vue (ou absente) : pas d'ALTER TABLE possible, on retire
    -- simplement les privilèges directs si elle existe encore.
    IF to_regclass('public.signalements_alertes') IS NOT NULL THEN
      REVOKE ALL ON public.signalements_alertes FROM anon, authenticated;
    END IF;
    RETURN;
  END IF;
  ALTER TABLE signalements_alertes ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'signalements_alertes'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.signalements_alertes', pol.policyname);
  END LOOP;
  EXECUTE $p$
    CREATE POLICY "signalements_alertes_admin" ON signalements_alertes
      FOR SELECT USING (public.is_admin_uid((auth.jwt() ->> 'sub')))
  $p$;
END $$;

-- ── bebes_portee (aucune référence code actuelle) ──────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  IF to_regclass('public.bebes_portee') IS NULL THEN RETURN; END IF;
  ALTER TABLE bebes_portee ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'bebes_portee'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.bebes_portee', pol.policyname);
  END LOOP;
  EXECUTE $p$
    CREATE POLICY "bebes_portee_owner_or_cogerant" ON bebes_portee
      FOR ALL USING (
        (auth.jwt() ->> 'sub') = uid_eleveur
        OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = bebes_portee.uid_eleveur AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
      )
      WITH CHECK (
        (auth.jwt() ->> 'sub') = uid_eleveur
        OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = bebes_portee.uid_eleveur AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
      )
  $p$;
END $$;

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN (
  'evenements','evenements_inscrits','creneaux_pro','zones_intervention',
  'prestations_education','prestations_photographe','prestations_toilettage',
  'credit_packs','radios','signalements_alertes','tache_commentaires','bebes_portee'
)
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN (
--       'evenements','evenements_inscrits','creneaux_pro','zones_intervention',
--       'prestations_education','prestations_photographe','prestations_toilettage',
--       'credit_packs','radios','signalements_alertes','tache_commentaires','bebes_portee'
--     )
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- ALTER TABLE evenements DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE evenements_inscrits DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE creneaux_pro DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE zones_intervention DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE prestations_education DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE prestations_photographe DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE prestations_toilettage DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE credit_packs DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE radios DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE tache_commentaires DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE bebes_portee DISABLE ROW LEVEL SECURITY;
-- GRANT SELECT ON public.signalements_alertes TO anon, authenticated;
