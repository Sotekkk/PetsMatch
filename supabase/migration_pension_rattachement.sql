-- Pension : fiche d'animal créée à l'entrée en pension pour un propriétaire
-- sans appli (pension_entrees.proprietaire_email) → proposée automatiquement
-- au propriétaire quand il se connecte avec la même adresse e-mail (route
-- /api/clients/rattachement), comme le fichier clients des autres pros.
-- rattachement_refuse_le : le propriétaire a refusé (plus de proposition).
-- Idempotent.
ALTER TABLE public.pension_entrees ADD COLUMN IF NOT EXISTS rattachement_refuse_le TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS pension_entrees_email_idx ON public.pension_entrees (lower(proprietaire_email));

NOTIFY pgrst, 'reload schema';
