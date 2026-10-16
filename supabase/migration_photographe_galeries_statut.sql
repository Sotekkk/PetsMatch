-- Photographe — statut des galeries (tableau de bord, étape 3 de la refonte).
-- Statuts retenus (cahier des charges §11.4, états inutiles écartés) :
--   brouillon        : galerie en préparation, pas encore partagée
--   partagee         : partagée au client, en attente de sa sélection
--   selection_recue  : le client a confirmé sa sélection → action du photographe
--   en_retouche      : finalisation des fichiers sélectionnés
--   livree           : fichiers finaux mis à disposition (≠ payée)
--   archivee         : close, partage désactivé
-- date_seance : date de la séance (rdv) ou saisie libre ; updated_at =
-- dernière activité. Idempotent.
ALTER TABLE public.albums_photo ADD COLUMN IF NOT EXISTS statut TEXT NOT NULL DEFAULT 'brouillon';
ALTER TABLE public.albums_photo ADD COLUMN IF NOT EXISTS date_seance DATE;
ALTER TABLE public.albums_photo ADD COLUMN IF NOT EXISTS couverture_url TEXT;
ALTER TABLE public.albums_photo ADD COLUMN IF NOT EXISTS selection_confirmee_le TIMESTAMPTZ;
ALTER TABLE public.albums_photo ADD COLUMN IF NOT EXISTS livree_le TIMESTAMPTZ;
ALTER TABLE public.albums_photo ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Reprise de l'existant : galerie avec un lien de partage actif = partagée ;
-- date de séance reprise du rendez-vous.
UPDATE public.albums_photo a SET statut = 'partagee'
  WHERE a.statut = 'brouillon'
    AND EXISTS (SELECT 1 FROM public.album_partage p WHERE p.album_id = a.id AND p.actif);
UPDATE public.albums_photo a SET date_seance = (r.date_heure AT TIME ZONE 'Europe/Paris')::date
  FROM public.rdv r WHERE a.rdv_id = r.id AND a.date_seance IS NULL;

CREATE INDEX IF NOT EXISTS idx_albums_photo_statut ON public.albums_photo (pro_profile_id, statut);

NOTIFY pgrst, 'reload schema';
