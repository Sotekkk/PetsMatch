-- Consignes du client avant un rendez-vous chez le toiletteur : questionnaire
-- rempli par le client dans l'appli ou depuis un lien personnel reçu par
-- e-mail (sans compte). Lecture / écriture uniquement par le serveur
-- (route /api/rdv/consignes : client du rdv, professionnel ou jeton).
--  • consignes          : réponses { cle: texte }
--  • consignes_le       : date de saisie par le client
--  • consignes_token    : lien personnel /consignes/<token>
--  • consignes_demandees_le : dernière demande envoyée par le professionnel
-- Idempotent.
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS consignes JSONB;
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS consignes_le TIMESTAMPTZ;
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS consignes_token UUID DEFAULT gen_random_uuid();
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS consignes_demandees_le TIMESTAMPTZ;
UPDATE public.rdv SET consignes_token = gen_random_uuid() WHERE consignes_token IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS rdv_consignes_token_idx ON public.rdv (consignes_token);

NOTIFY pgrst, 'reload schema';
