-- Photographe — relance du client qui n'a pas confirmé sa sélection.
-- albums_photo.relance_selection_le : dernière relance (bouton « Relancer le
-- client » ou rappel automatique tous les 3 jours, Cloud Function
-- purgerLivraisonsPhoto) tant que la galerie est partagée sans sélection
-- confirmée. Idempotent.
ALTER TABLE public.albums_photo ADD COLUMN IF NOT EXISTS relance_selection_le TIMESTAMPTZ;

NOTIFY pgrst, 'reload schema';
