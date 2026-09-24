-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 37/N : natural_places, natural_place_reviews,
--   natural_place_photo_suggestions, natural_place_amenity_suggestions,
--   catfiche, dogfiche
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- natural_places (lieux naturels, proposition modérée — spec module
-- forêts/plages/parcs) : lecture publique pour les lieux validés
-- (statut = 'valide'), + son propre lieu proposé (en attente/refusé) pour
-- le proposant, + tout pour l'admin (is_admin_uid — le back-office
-- /admin lit/écrit directement via le client anon, pas de route
-- service_role, confirmé dans admin/page.tsx).
-- Écriture : proposant (sa proposition) OU admin (modération) OU, POINT
-- IMPORTANT, tout utilisateur connecté sur un lieu déjà VALIDÉ — c'est le
-- flux de signalement d'alerte cyanobactéries (CyanoReportModal.tsx),
-- ouvert à n'importe quel compte connecté, pas seulement au proposant du
-- lieu. La RLS ne peut pas restreindre aux seules colonnes alerte_cyano_*
-- (pas de contrôle colonne par colonne sans trigger) — un compte connecté
-- malveillant pourrait donc aussi modifier nom/description/coordonnées
-- d'un lieu déjà validé. Risque accepté (nécessite un compte réel,
-- traçable) plutôt que casser le signalement cyano ; blocage total
-- cependant pour l'anonyme et pour toute proposition non encore validée.
--
-- natural_place_reviews : lecture publique (avis), écriture par son auteur
-- — la colonne `profile_id` stocke en réalité l'uid brut (confirmé dans
-- natural_place_detail_page.dart : `'profile_id': _uid`), pas un vrai
-- profile_id malgré le nom.
--
-- natural_place_photo_suggestions / natural_place_amenity_suggestions
-- (contributions modérées) : jamais publiques (fusionnées dans
-- natural_places une fois validées) — réservé au contributeur + admin.
--
-- catfiche / dogfiche : AUCUNE référence dans le code actuel (ancien
-- modèle par espèce, remplacé par la table unifiée `animaux`) — verrouillé
-- par sécurité (uid_eleveur), sans impact fonctionnel connu.
--
-- ⚠️ À TESTER après exécution :
--   1. La carte des lieux naturels reste publique (lieux validés) ; ma
--      proposition en attente reste visible pour moi seul.
--   2. Proposer un lieu, déposer un avis/une suggestion de photo/
--      équipement fonctionne.
--   3. Signaler une alerte cyanobactéries sur un lieu existant fonctionne.
--   4. La modération admin (valider/refuser un lieu ou une suggestion)
--      fonctionne toujours.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── natural_places ──────────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE natural_places ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'natural_places'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.natural_places', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "natural_places_select" ON natural_places
  FOR SELECT USING (
    statut = 'valide'
    OR (auth.jwt() ->> 'sub') = submitted_by_uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );
CREATE POLICY "natural_places_insert" ON natural_places
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = submitted_by_uid);
CREATE POLICY "natural_places_update" ON natural_places
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = submitted_by_uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
    OR (statut = 'valide' AND (auth.jwt() ->> 'sub') IS NOT NULL)
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = submitted_by_uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
    OR (statut = 'valide' AND (auth.jwt() ->> 'sub') IS NOT NULL)
  );
CREATE POLICY "natural_places_delete" ON natural_places
  FOR DELETE USING (public.is_admin_uid((auth.jwt() ->> 'sub')));

-- ── natural_place_reviews (profile_id contient en réalité l'uid) ──────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE natural_place_reviews ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'natural_place_reviews'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.natural_place_reviews', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "natural_place_reviews_select" ON natural_place_reviews FOR SELECT USING (true);
CREATE POLICY "natural_place_reviews_write" ON natural_place_reviews
  FOR ALL USING ((auth.jwt() ->> 'sub') = profile_id) WITH CHECK ((auth.jwt() ->> 'sub') = profile_id);

-- ── natural_place_photo_suggestions (contributeur + admin) ────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE natural_place_photo_suggestions ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'natural_place_photo_suggestions'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.natural_place_photo_suggestions', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "natural_place_photo_suggestions_select" ON natural_place_photo_suggestions
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = submitted_by_uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );
CREATE POLICY "natural_place_photo_suggestions_insert" ON natural_place_photo_suggestions
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = submitted_by_uid);
CREATE POLICY "natural_place_photo_suggestions_update" ON natural_place_photo_suggestions
  FOR UPDATE USING (public.is_admin_uid((auth.jwt() ->> 'sub')))
  WITH CHECK (public.is_admin_uid((auth.jwt() ->> 'sub')));

-- ── natural_place_amenity_suggestions (contributeur + admin) ──────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE natural_place_amenity_suggestions ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'natural_place_amenity_suggestions'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.natural_place_amenity_suggestions', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "natural_place_amenity_suggestions_select" ON natural_place_amenity_suggestions
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = submitted_by_uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );
CREATE POLICY "natural_place_amenity_suggestions_insert" ON natural_place_amenity_suggestions
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = submitted_by_uid);
CREATE POLICY "natural_place_amenity_suggestions_update" ON natural_place_amenity_suggestions
  FOR UPDATE USING (public.is_admin_uid((auth.jwt() ->> 'sub')))
  WITH CHECK (public.is_admin_uid((auth.jwt() ->> 'sub')));

-- ── catfiche / dogfiche (aucune référence code actuelle) ───────────────────
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['catfiche','dogfiche']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;
    EXECUTE format($f$
      CREATE POLICY "%1$s_owner_or_cogerant" ON public.%1$I
        FOR ALL USING (
          (auth.jwt() ->> 'sub') = uid_eleveur
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = %1$I.uid_eleveur AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
        WITH CHECK (
          (auth.jwt() ->> 'sub') = uid_eleveur
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = %1$I.uid_eleveur AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    $f$, t);
  END LOOP;
END $$;

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN (
  'natural_places','natural_place_reviews','natural_place_photo_suggestions',
  'natural_place_amenity_suggestions','catfiche','dogfiche'
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
--       'natural_places','natural_place_reviews','natural_place_photo_suggestions',
--       'natural_place_amenity_suggestions','catfiche','dogfiche'
--     )
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- ALTER TABLE natural_places DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE natural_place_reviews DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE natural_place_photo_suggestions DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE natural_place_amenity_suggestions DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE catfiche DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE dogfiche DISABLE ROW LEVEL SECURITY;
