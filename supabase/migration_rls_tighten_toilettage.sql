-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 20/N : toilettage
--   fiches_toilettage, fiches_toilettage_photos, toilettage_factures,
--   postes_toilettage
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- Ces 4 tables ont des colonnes client_uid/animal_id, mais aucune n'est
-- lue côté particulier dans le code actuel (fiches_toilettage_photos.dart /
-- mes-animaux/[id] ne les consultent pas) — usage 100% interne au
-- toiletteur. Modèle : pro (pro_uid) ou cogérant actif uniquement, comme
-- pension_entrees/cles_clients (vague 18/N).
--
-- ⚠️ À TESTER après exécution :
--   1. Les fiches de toilettage (préférences, allergies, coupe), leurs
--      photos avant/après, la facturation et la liste des postes
--      s'affichent normalement pour le pro et un cogérant actif.
--   2. Créer/modifier une fiche, ajouter une photo, créer/modifier une
--      facture fonctionnent toujours.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── fiches_toilettage, toilettage_factures, postes_toilettage (pro_uid direct) ──
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['fiches_toilettage','toilettage_factures','postes_toilettage']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
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

-- ── fiches_toilettage_photos (rattachée via fiche_id) ──────────────────────
ALTER TABLE fiches_toilettage_photos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "fiches_toilettage_photos_all" ON fiches_toilettage_photos;

CREATE POLICY "fiches_toilettage_photos_related" ON fiches_toilettage_photos
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM fiches_toilettage f
      WHERE f.id = fiches_toilettage_photos.fiche_id
        AND (
          f.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = f.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM fiches_toilettage f
      WHERE f.id = fiches_toilettage_photos.fiche_id
        AND (
          f.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = f.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  );

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('fiches_toilettage','fiches_toilettage_photos','toilettage_factures','postes_toilettage')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('fiches_toilettage','fiches_toilettage_photos','toilettage_factures','postes_toilettage')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- CREATE POLICY "fiches_toilettage_photos_all" ON fiches_toilettage_photos FOR ALL USING (true);
-- CREATE POLICY "postes_toilettage_all" ON postes_toilettage FOR ALL USING (true);
