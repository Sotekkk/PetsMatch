-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 36/N : albums_photo, album_photos, album_partage,
--   agenda_retards
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- albums_photo / album_photos (galerie livrée par un photographe à son
-- client, photographe_album_page.dart) : jamais protégées jusqu'ici.
-- Lecture réservée au pro (pro_uid/cogérant), au client (client_uid), OU à
-- quiconque possède un lien de partage ACTIF pour l'album
-- (website/src/app/album/[token]/page.tsx — lecture anonyme directe côté
-- client web, sans passer par une route API service_role).
--
-- ⚠️ Limite connue : la page web valide le token via une 1ʳᵉ requête sur
-- album_partage, puis récupère les photos par une 2ᵉ requête simple sur
-- album_id — la RLS ne peut pas vérifier que l'appelant a bien fourni CE
-- token précis (elle n'y a pas accès), seulement qu'un partage actif
-- existe pour cet album. Amélioration réelle par rapport à l'ouverture
-- totale précédente (un album jamais partagé, ou dont le lien a été
-- désactivé/expiré, redevient invisible), mais pas une vraie confidentialité
-- par token — comme pour devis/cessions, corriger complètement nécessiterait
-- de faire transiter cette lecture par une route API dédiée. Non bloquant
-- ici (lecture seule, pas d'écriture en jeu).
--
-- album_partage : lecture publique nécessaire (c'est la 1ʳᵉ requête de la
-- page /album/[token], avant même de connaître l'album) — écriture
-- (créer/désactiver un lien) réservée au pro de l'album/cogérant.
--
-- agenda_retards : AUCUNE référence dans le code actuel — verrouillé par
-- sécurité (pro_uid), sans impact fonctionnel connu.
--
-- ⚠️ À TESTER après exécution :
--   1. Le photographe peut créer un album, y ajouter/retirer des photos,
--      générer un lien de partage.
--   2. Le lien /album/[token] partagé affiche toujours les photos pour un
--      visiteur non connecté.
--   3. Désactiver un lien de partage le rend bien inaccessible.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── albums_photo ────────────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE albums_photo ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'albums_photo'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.albums_photo', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "albums_photo_select" ON albums_photo
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR (auth.jwt() ->> 'sub') = client_uid
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = albums_photo.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
    OR EXISTS (SELECT 1 FROM album_partage ap WHERE ap.album_id = albums_photo.id AND ap.actif = true AND (ap.expire_at IS NULL OR ap.expire_at > now()))
  );
CREATE POLICY "albums_photo_write" ON albums_photo
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = albums_photo.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = albums_photo.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  );

-- ── album_photos (photos individuelles, rattachées via album_id) ─────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE album_photos ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'album_photos'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.album_photos', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "album_photos_select" ON album_photos
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM albums_photo a
      WHERE a.id = album_photos.album_id
        AND (
          a.pro_uid = (auth.jwt() ->> 'sub')
          OR a.client_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = a.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    )
    OR EXISTS (SELECT 1 FROM album_partage ap WHERE ap.album_id = album_photos.album_id AND ap.actif = true AND (ap.expire_at IS NULL OR ap.expire_at > now()))
  );
CREATE POLICY "album_photos_write" ON album_photos
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM albums_photo a
      WHERE a.id = album_photos.album_id
        AND (
          a.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = a.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM albums_photo a
      WHERE a.id = album_photos.album_id
        AND (
          a.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = a.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    )
  );

-- ── album_partage (lecture publique nécessaire au flux token) ────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE album_partage ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'album_partage'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.album_partage', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "album_partage_select" ON album_partage FOR SELECT USING (true);
CREATE POLICY "album_partage_write" ON album_partage
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM albums_photo a
      WHERE a.id = album_partage.album_id
        AND (
          a.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = a.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM albums_photo a
      WHERE a.id = album_partage.album_id
        AND (
          a.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = a.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    )
  );

-- ── agenda_retards (aucune référence code actuelle) ────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  IF to_regclass('public.agenda_retards') IS NULL THEN RETURN; END IF;
  ALTER TABLE agenda_retards ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'agenda_retards'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.agenda_retards', pol.policyname);
  END LOOP;
  EXECUTE $p$
    CREATE POLICY "agenda_retards_owner" ON agenda_retards
      FOR ALL USING ((auth.jwt() ->> 'sub') = pro_uid)
      WITH CHECK ((auth.jwt() ->> 'sub') = pro_uid)
  $p$;
END $$;

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('albums_photo','album_photos','album_partage','agenda_retards')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('albums_photo','album_photos','album_partage','agenda_retards')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- ALTER TABLE albums_photo DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE album_photos DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE album_partage DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE agenda_retards DISABLE ROW LEVEL SECURITY;
