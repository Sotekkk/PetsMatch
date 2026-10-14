-- Pet-sitting : demande de réservation enrichie (appli + site).
--   serie_id       : regroupe les passages d'une même demande (fréquence
--                    hebdo / certains jours / tous les jours, plusieurs
--                    horaires par jour) — le pet-sitter accepte la série en une fois.
--   animaux_ids    : colonne JSONB existante (migration_rdv_animaux_ids.sql,
--                    taxi) réutilisée : tous les animaux (animal_id = le premier) ;
--                    animal_nom_manuel porte les noms (« Luna + Rex »).
--   acces_logement : present | remise_cles | boite_cles | cles_detenues
--                    (jamais de code de boîte à clés ici : gestion des clés).
--   forfait_id     : forfait choisi par le client (forfaits_garde).
-- Idempotent.
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS serie_id UUID;
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS animaux_ids JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS acces_logement TEXT;
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS forfait_id UUID;

DO $$ BEGIN
  ALTER TABLE public.rdv ADD CONSTRAINT rdv_acces_logement_chk
    CHECK (acces_logement IS NULL OR acces_logement IN ('present', 'remise_cles', 'boite_cles', 'cles_detenues'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE public.rdv ADD CONSTRAINT rdv_forfait_garde_fk
    FOREIGN KEY (forfait_id) REFERENCES public.forfaits_garde(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS rdv_serie_id_idx ON public.rdv (serie_id) WHERE serie_id IS NOT NULL;

NOTIFY pgrst, 'reload schema';
