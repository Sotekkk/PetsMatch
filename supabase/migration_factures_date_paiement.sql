-- Facture acquittée : date de règlement (le mode est déjà dans mode_paiement).
-- Colonnes hors du verrou d'inaltérabilité (factures_garde_fou) : modifiables
-- après émission, comme le statut payée. Mention « ACQUITTÉE le … » sur le PDF.
-- Idempotent.
ALTER TABLE public.factures ADD COLUMN IF NOT EXISTS date_paiement timestamptz;
