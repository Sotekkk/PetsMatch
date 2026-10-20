-- Pension — journée d'essai avant le premier séjour (réservation en ligne) :
-- la ligne de pension_entrees créée pour l'essai est marquée, pour l'afficher
-- « essai » dans Nos pensionnaires. Idempotent.
-- Pré-requis : migration_pension_fiche.sql (consignes_sejour, arrivée / départ réels).
ALTER TABLE public.pension_entrees ADD COLUMN IF NOT EXISTS essai BOOLEAN NOT NULL DEFAULT false;
UPDATE public.pension_entrees SET essai = true WHERE notes = 'Essai avant le premier séjour' AND essai = false;
NOTIFY pgrst, 'reload schema';
