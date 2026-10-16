-- Photographe — sélection client et livraison (étape 5 de la refonte).
-- Sélection : le client coche ses photos (album_photos.selectionnee) via le
-- serveur ; rien n'est définitif avant sa confirmation explicite
-- (albums_photo.selection_confirmee_le, statut « selection_recue »).
-- Livraison : les fichiers finaux achetés sont remis en ZIP (parties de
-- 45 Mo max) dans le bucket PRIVÉ « livraisons », STOCKAGE TEMPORAIRE :
-- téléchargement par le seul client (URL signée de 10 min délivrée par le
-- serveur), date d'expiration affichée au client et au photographe, rappel
-- 3 jours avant, puis suppression automatique (Cloud Function
-- purgerLivraisonsPhoto). Les aperçus de la galerie ne sont pas touchés.
-- Une galerie livrée n'est jamais considérée comme payée. Idempotent.

INSERT INTO storage.buckets (id, name, public)
VALUES ('livraisons', 'livraisons', false)
ON CONFLICT (id) DO UPDATE SET public = false;

ALTER TABLE public.album_photos ADD COLUMN IF NOT EXISTS selectionnee BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.albums_photo ADD COLUMN IF NOT EXISTS nb_photos_incluses INTEGER;
ALTER TABLE public.albums_photo ADD COLUMN IF NOT EXISTS selection_commentaire TEXT;

CREATE TABLE IF NOT EXISTS public.album_livraisons (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  album_id        UUID NOT NULL REFERENCES public.albums_photo(id) ON DELETE CASCADE,
  numero          INTEGER NOT NULL DEFAULT 1,
  storage_path    TEXT NOT NULL,
  nom_fichier     TEXT NOT NULL,
  taille_octets   BIGINT,
  nb_fichiers     INTEGER,
  expire_le       TIMESTAMPTZ NOT NULL,
  rappel_envoye   BOOLEAN NOT NULL DEFAULT false,
  telechargements INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_album_livraisons_album ON public.album_livraisons (album_id);
CREATE INDEX IF NOT EXISTS idx_album_livraisons_expire ON public.album_livraisons (expire_le);

-- Lecture par le photographe uniquement ; le client passe par le serveur.
ALTER TABLE public.album_livraisons ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "album_livraisons_pro" ON public.album_livraisons;
CREATE POLICY "album_livraisons_pro" ON public.album_livraisons FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.albums_photo a WHERE a.id = album_livraisons.album_id
    AND ((auth.jwt() ->> 'sub') = a.pro_uid
      OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = a.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL))));

NOTIFY pgrst, 'reload schema';
