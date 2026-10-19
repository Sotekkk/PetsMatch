-- Pension — réservation de séjour : le client indique si son animal est déjà
-- venu dans la pension (cas des animaux accueillis avant PetsMatch, absents de
-- l'historique pension_entrees). null = historique connu, question non posée.
-- Équidés : hébergement souhaité par le client (box / pré).
-- Idempotent.
ALTER TABLE public.pension_demandes ADD COLUMN IF NOT EXISTS nouveau_pensionnaire BOOLEAN;
ALTER TABLE public.pension_demandes ADD COLUMN IF NOT EXISTS hebergement TEXT;
NOTIFY pgrst, 'reload schema';
