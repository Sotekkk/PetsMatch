-- Devis rattaché à une séance (rdv) — photographe et autres métiers à
-- séance : le dossier de la séance réunit devis, contrat, galerie et
-- facture. Facultatif (un devis peut précéder toute réservation). Idempotent.
ALTER TABLE public.devis ADD COLUMN IF NOT EXISTS rdv_id UUID REFERENCES public.rdv(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_devis_rdv ON public.devis (rdv_id);

NOTIFY pgrst, 'reload schema';
