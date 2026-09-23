-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 34/N : Perdus/Trouvés + Pet-Friendly
--   alertes_perdus, animaux_trouves, alertes_correspondances,
--   petfriendly_places, petfriendly_reviews, petfriendly_review_contests,
--   place_favoris, place_likes, place_disponibilites
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- alertes_perdus / animaux_trouves : lecture PUBLIQUE conservée (c'est tout
-- l'intérêt de la fonctionnalité — un inconnu doit pouvoir voir l'alerte,
-- ses coordonnées de contact incluses, pour signaler l'animal). Écriture
-- verrouillée à son déclarant (uid_proprietaire / user_uid) — confirmé,
-- aucun chemin d'écriture anonyme dans le code (déclaration exige un
-- compte connecté, app + site).
--
-- alertes_correspondances (résultats de rapprochement algorithmique) :
-- jamais écrite côté client (functions/match.js, clé service_role) —
-- seule la LECTURE compte ici, réservée aux deux parties concernées
-- (propriétaire de l'alerte perdue + déclarant de l'animal trouvé).
--
-- petfriendly_places : lecture publique (annuaire), écriture pro/cogérant
-- — même modèle que forfaits_garde/chenil_boxes (élevage_cogerants
-- généralisé à tout uid pro, pas seulement éleveur).
--
-- petfriendly_reviews : lecture publique (avis), écriture par l'auteur ;
-- UPDATE/DELETE aussi ouvert au pro du lieu concerné — confirmé dans
-- lieu_detail_page.dart (_AvisDetailSheet : isOwner OU isPlaceOwner peut
-- supprimer), et mon_etablissement_page.dart supprime tous les avis d'un
-- lieu à sa suppression (nécessite ce droit pro, sinon suppression
-- partielle silencieuse).
--
-- petfriendly_review_contests (contestation d'avis par le pro) : réservé
-- au pro contestataire (uid_pro) + admin ; aucune écriture de décision
-- côté client actuellement (à traiter manuellement / futur back-office).
--
-- place_favoris : liste personnelle privée (jamais lue pour un autre uid).
-- Note : mon_etablissement_page.dart supprime aussi tous les favoris d'un
-- lieu à sa suppression sans filtrer par uid — ce verrouillage self-only
-- laissera ces lignes orphelines dans ce cas précis (nettoyage cosmétique
-- manqué, pas un problème de sécurité).
--
-- place_likes : lecture publique (compteur de likes, comme post_likes/
-- story_likes), écriture self.
--
-- place_disponibilites : lecture publique (un visiteur doit voir les
-- disponibilités avant de réserver), écriture pro/cogérant du lieu.
--
-- ⚠️ À TESTER après exécution :
--   1. Le fil Perdus/Trouvés reste visible publiquement (carte, contact) ;
--      déclarer/modifier/clôturer une alerte fonctionne pour son auteur.
--   2. Mes Alertes affiche toujours les rapprochements (correspondances)
--      pour l'alerte perdue ET pour l'animal trouvé.
--   3. L'annuaire Pet-Friendly reste public ; gérer son établissement
--      (fiche, avis, disponibilités) fonctionne pour le pro/cogérant.
--   4. Favoris/likes d'un lieu fonctionnent normalement pour l'utilisateur.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── alertes_perdus ──────────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE alertes_perdus ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'alertes_perdus'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.alertes_perdus', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "alertes_perdus_select" ON alertes_perdus FOR SELECT USING (true);
CREATE POLICY "alertes_perdus_write" ON alertes_perdus
  FOR ALL USING ((auth.jwt() ->> 'sub') = uid_proprietaire)
  WITH CHECK ((auth.jwt() ->> 'sub') = uid_proprietaire);

-- ── animaux_trouves ─────────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE animaux_trouves ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'animaux_trouves'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.animaux_trouves', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "animaux_trouves_select" ON animaux_trouves FOR SELECT USING (true);
CREATE POLICY "animaux_trouves_write" ON animaux_trouves
  FOR ALL USING ((auth.jwt() ->> 'sub') = user_uid)
  WITH CHECK ((auth.jwt() ->> 'sub') = user_uid);

-- ── alertes_correspondances (lecture par les deux parties concernées) ─────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE alertes_correspondances ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'alertes_correspondances'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.alertes_correspondances', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "alertes_correspondances_select" ON alertes_correspondances
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM alertes_perdus a WHERE a.id = alertes_correspondances.alerte_id AND a.uid_proprietaire = (auth.jwt() ->> 'sub'))
    OR EXISTS (SELECT 1 FROM animaux_trouves t WHERE t.id::text = alertes_correspondances.trouve_id AND t.user_uid = (auth.jwt() ->> 'sub'))
  );

-- ── petfriendly_places (annuaire public, écriture pro/cogérant) ──────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE petfriendly_places ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'petfriendly_places'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.petfriendly_places', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "petfriendly_places_select" ON petfriendly_places FOR SELECT USING (true);
CREATE POLICY "petfriendly_places_write" ON petfriendly_places
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = uid_pro
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = petfriendly_places.uid_pro AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_pro
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = petfriendly_places.uid_pro AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  );

-- ── petfriendly_reviews (avis public, auteur OU pro du lieu) ──────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE petfriendly_reviews ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'petfriendly_reviews'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.petfriendly_reviews', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "petfriendly_reviews_select" ON petfriendly_reviews FOR SELECT USING (true);
CREATE POLICY "petfriendly_reviews_insert" ON petfriendly_reviews
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = user_uid);
CREATE POLICY "petfriendly_reviews_update" ON petfriendly_reviews
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = user_uid
    OR EXISTS (
      SELECT 1 FROM petfriendly_places p
      WHERE p.id = petfriendly_reviews.place_id
        AND (p.uid_pro = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = p.uid_pro AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL))
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = user_uid
    OR EXISTS (
      SELECT 1 FROM petfriendly_places p
      WHERE p.id = petfriendly_reviews.place_id
        AND (p.uid_pro = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = p.uid_pro AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL))
    )
  );
CREATE POLICY "petfriendly_reviews_delete" ON petfriendly_reviews
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = user_uid
    OR EXISTS (
      SELECT 1 FROM petfriendly_places p
      WHERE p.id = petfriendly_reviews.place_id
        AND (p.uid_pro = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = p.uid_pro AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL))
    )
  );

-- ── petfriendly_review_contests (pro contestataire + admin) ──────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE petfriendly_review_contests ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'petfriendly_review_contests'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.petfriendly_review_contests', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "petfriendly_review_contests_select" ON petfriendly_review_contests
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = uid_pro
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );
CREATE POLICY "petfriendly_review_contests_insert" ON petfriendly_review_contests
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = uid_pro);
CREATE POLICY "petfriendly_review_contests_update" ON petfriendly_review_contests
  FOR UPDATE USING (public.is_admin_uid((auth.jwt() ->> 'sub')))
  WITH CHECK (public.is_admin_uid((auth.jwt() ->> 'sub')));

-- ── place_favoris (privé au propriétaire) ─────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE place_favoris ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'place_favoris'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.place_favoris', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "place_favoris_owner" ON place_favoris
  FOR ALL USING ((auth.jwt() ->> 'sub') = user_uid) WITH CHECK ((auth.jwt() ->> 'sub') = user_uid);

-- ── place_likes (lecture publique, écriture self) ─────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE place_likes ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'place_likes'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.place_likes', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "place_likes_select" ON place_likes FOR SELECT USING (true);
CREATE POLICY "place_likes_write" ON place_likes
  FOR ALL USING ((auth.jwt() ->> 'sub') = user_uid) WITH CHECK ((auth.jwt() ->> 'sub') = user_uid);

-- ── place_disponibilites (lecture publique, écriture pro/cogérant du lieu) ─
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE place_disponibilites ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'place_disponibilites'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.place_disponibilites', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "place_disponibilites_select" ON place_disponibilites FOR SELECT USING (true);
CREATE POLICY "place_disponibilites_write" ON place_disponibilites
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM petfriendly_places p
      WHERE p.id::text = place_disponibilites.place_id
        AND (p.uid_pro = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = p.uid_pro AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL))
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM petfriendly_places p
      WHERE p.id::text = place_disponibilites.place_id
        AND (p.uid_pro = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = p.uid_pro AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL))
    )
  );

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN (
  'alertes_perdus','animaux_trouves','alertes_correspondances','petfriendly_places',
  'petfriendly_reviews','petfriendly_review_contests','place_favoris','place_likes','place_disponibilites'
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
--       'alertes_perdus','animaux_trouves','alertes_correspondances','petfriendly_places',
--       'petfriendly_reviews','petfriendly_review_contests','place_favoris','place_likes','place_disponibilites'
--     )
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- ALTER TABLE alertes_perdus DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE animaux_trouves DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE alertes_correspondances DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE petfriendly_places DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE petfriendly_reviews DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE petfriendly_review_contests DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE place_favoris DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE place_likes DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE place_disponibilites DISABLE ROW LEVEL SECURITY;
