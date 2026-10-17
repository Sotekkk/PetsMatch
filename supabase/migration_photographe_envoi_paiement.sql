-- Photographe — envoi par e-mail et paiement avant livraison.
--  • albums_photo.client_email : adresse du client (préremplie depuis son
--    profil ou le rendez-vous, modifiable) : galerie, facture et livraison
--    lui sont envoyées par e-mail, y compris s'il n'a pas l'application.
--  • album_livraisons.prolongee : la livraison (stockage temporaire, 500 Mo
--    max, 3 / 7 / 14 jours) ne peut être prolongée qu'une fois.
-- La livraison est bloquée tant que la facture de la séance n'est pas payée
-- (le photographe peut forcer) ; la facture acquittée est jointe à l'e-mail.
-- Idempotent.

ALTER TABLE public.albums_photo ADD COLUMN IF NOT EXISTS client_email TEXT;
ALTER TABLE public.album_livraisons ADD COLUMN IF NOT EXISTS prolongee BOOLEAN NOT NULL DEFAULT false;

NOTIFY pgrst, 'reload schema';
