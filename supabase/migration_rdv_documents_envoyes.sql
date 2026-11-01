-- Fin de séance / de consultation : date d'envoi des documents au client
-- (« Terminer et envoyer »), affichée dans le dossier de la séance pour savoir
-- si c'est parti. 01/11/2026. Idempotent.

ALTER TABLE public.rdv
  ADD COLUMN IF NOT EXISTS documents_envoyes_le timestamptz;

COMMENT ON COLUMN public.rdv.documents_envoyes_le IS 'Dernier envoi réussi des documents de fin de séance au client';
