-- Photographe — galerie côté client : coups de cœur et partage aux proches.
--  • album_photos.aimee : photo aimée par le client (coup de cœur), distincte
--    de la sélection (album_photos.selectionnee, qui engage la commande).
--    Les photos aimées et sélectionnées apparaissent dans Mes favoris,
--    onglet « Shootings ».
--  • album_partage.type : 'client' (lien privé créé par le photographe :
--    sélection et téléchargement possibles) ou 'proches' (lien créé par le
--    client pour sa famille : consultation seule, aperçus toujours avec
--    filigrane, ni sélection ni téléchargement de la livraison).
-- Écritures par le serveur uniquement (routes /api/galeries/*). Idempotent.

ALTER TABLE public.album_photos ADD COLUMN IF NOT EXISTS aimee BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.album_partage ADD COLUMN IF NOT EXISTS type TEXT NOT NULL DEFAULT 'client';
ALTER TABLE public.album_partage ADD COLUMN IF NOT EXISTS cree_par_uid TEXT;
DO $$ BEGIN
  ALTER TABLE public.album_partage ADD CONSTRAINT album_partage_type_check CHECK (type IN ('client', 'proches'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

NOTIFY pgrst, 'reload schema';
