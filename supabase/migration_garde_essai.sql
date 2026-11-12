-- Pet-sitter — visite d'essai pour un nouveau client (12/11/2026), comme
-- l'essai de la pension.
--   Réglages (user_profiles.tarifs_garde, JSON existant, pas de colonne) :
--     essai_actif (1/0), essai (prix TTC), essai_duree (minutes),
--     essai_obligatoire (1/0 : un nouveau client ne réserve que l'essai).
--   RDV d'essai : rdv.est_essai ; résultat posé par le pet-sitter :
--     essai_resultat ('concluant' | 'non_concluant'), essai_motif, essai_resultat_le.
-- Site : lib/garde-essai.ts ; appli : lib/utils/garde_essai.dart.
-- Idempotent.
BEGIN;
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS est_essai BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS essai_resultat TEXT
  CHECK (essai_resultat IS NULL OR essai_resultat IN ('concluant', 'non_concluant'));
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS essai_motif TEXT;
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS essai_resultat_le TIMESTAMPTZ;
NOTIFY pgrst, 'reload schema';
COMMIT;

-- ROLLBACK
-- ALTER TABLE public.rdv DROP COLUMN IF EXISTS essai_resultat_le, DROP COLUMN IF EXISTS essai_motif,
--   DROP COLUMN IF EXISTS essai_resultat, DROP COLUMN IF EXISTS est_essai;
