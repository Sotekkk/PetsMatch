-- Prestations sur mesure du pet-sitter / promeneur (module garde).
-- Même modèle que tarifs_education_extra : liste JSONB de {label, prix, description}.
-- Idempotent.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS tarifs_garde_extra jsonb DEFAULT '[]'::jsonb;

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS tarifs_garde_extra jsonb DEFAULT '[]'::jsonb;
