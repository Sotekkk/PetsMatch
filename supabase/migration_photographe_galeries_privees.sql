-- Photographe — galeries privées clients (étape 4 de la refonte).
-- Principes (validés) :
--   • Réservé au photographe Premium (abonnement photographe actif payant),
--     contrôlé côté serveur (routes /api/galeries/*).
--   • On ne stocke durablement que des APERÇUS compressés (≈1600 px, filigrane
--     facultatif) dans le bucket PRIVÉ « galeries » : aucune URL publique,
--     accès uniquement par URL signée courte délivrée par le serveur après
--     contrôle (photographe, client destinataire, ou lien privé valide).
--   • Les fichiers achetés (étape 5) passeront par un stockage temporaire
--     (ZIP protégé), jamais par ce bucket.
--   • Galeries jamais publiques ni indexables ; jamais publiées
--     automatiquement dans le portfolio.
-- Idempotent.

-- 1. Bucket privé (aucune policy storage : seul le service role y accède).
INSERT INTO storage.buckets (id, name, public)
VALUES ('galeries', 'galeries', false)
ON CONFLICT (id) DO UPDATE SET public = false;

-- 2. Galerie : paramètres d'accès.
ALTER TABLE public.albums_photo ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE public.albums_photo ADD COLUMN IF NOT EXISTS filigrane BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.albums_photo ADD COLUMN IF NOT EXISTS partage_client BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.albums_photo ADD COLUMN IF NOT EXISTS partagee_le TIMESTAMPTZ;
ALTER TABLE public.albums_photo ALTER COLUMN titre SET DEFAULT 'Séance photo';

-- 3. Photos : chemin privé + métadonnées (doublons, proportions, ordre).
ALTER TABLE public.album_photos ADD COLUMN IF NOT EXISTS storage_path TEXT;
ALTER TABLE public.album_photos ADD COLUMN IF NOT EXISTS nom_fichier TEXT;
ALTER TABLE public.album_photos ADD COLUMN IF NOT EXISTS taille_octets BIGINT;
ALTER TABLE public.album_photos ADD COLUMN IF NOT EXISTS largeur INTEGER;
ALTER TABLE public.album_photos ADD COLUMN IF NOT EXISTS hauteur INTEGER;
ALTER TABLE public.album_photos ADD COLUMN IF NOT EXISTS ordre INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.album_photos ALTER COLUMN photo_url DROP NOT NULL;
CREATE INDEX IF NOT EXISTS idx_album_photos_ordre ON public.album_photos (album_id, ordre);

-- 4. Accès : fin du « USING (true) ». Le photographe (ou un cogérant actif)
--    gère ses galeries ; le client lit la fiche de SA galerie une fois
--    partagée. Les photos et les liens privés ne sont lus que par le
--    photographe — le client passe par le serveur (URL signées).
DROP POLICY IF EXISTS "albums_photo_all" ON public.albums_photo;
DROP POLICY IF EXISTS "albums_photo_pro" ON public.albums_photo;
CREATE POLICY "albums_photo_pro" ON public.albums_photo FOR ALL
  USING ((auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = albums_photo.pro_uid
      AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL))
  WITH CHECK ((auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = albums_photo.pro_uid
      AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL));
DROP POLICY IF EXISTS "albums_photo_client" ON public.albums_photo;
CREATE POLICY "albums_photo_client" ON public.albums_photo FOR SELECT
  USING (partage_client AND statut <> 'brouillon' AND client_uid = (auth.jwt() ->> 'sub'));

DROP POLICY IF EXISTS "album_photos_all" ON public.album_photos;
DROP POLICY IF EXISTS "album_photos_pro" ON public.album_photos;
CREATE POLICY "album_photos_pro" ON public.album_photos FOR ALL
  USING (EXISTS (SELECT 1 FROM public.albums_photo a WHERE a.id = album_photos.album_id
    AND ((auth.jwt() ->> 'sub') = a.pro_uid
      OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = a.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL))))
  WITH CHECK (EXISTS (SELECT 1 FROM public.albums_photo a WHERE a.id = album_photos.album_id
    AND ((auth.jwt() ->> 'sub') = a.pro_uid
      OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = a.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL))));

DROP POLICY IF EXISTS "album_partage_all" ON public.album_partage;
DROP POLICY IF EXISTS "album_partage_pro" ON public.album_partage;
CREATE POLICY "album_partage_pro" ON public.album_partage FOR ALL
  USING (EXISTS (SELECT 1 FROM public.albums_photo a WHERE a.id = album_partage.album_id
    AND (auth.jwt() ->> 'sub') = a.pro_uid))
  WITH CHECK (EXISTS (SELECT 1 FROM public.albums_photo a WHERE a.id = album_partage.album_id
    AND (auth.jwt() ->> 'sub') = a.pro_uid));

NOTIFY pgrst, 'reload schema';
