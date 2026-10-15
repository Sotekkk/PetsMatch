-- Fiche éducative (éducateur / comportementaliste) — étape 2 de
-- l'harmonisation des fiches animaux professionnelles. Idempotent.

-- 1. Objectifs : 5 statuts (le professionnel renseigne la progression, aucun
--    pourcentage calculé) + objectif prioritaire + difficultés rencontrées.
ALTER TABLE public.education_objectifs DROP CONSTRAINT IF EXISTS education_objectifs_statut_check;
ALTER TABLE public.education_objectifs ADD CONSTRAINT education_objectifs_statut_check
  CHECK (statut IN ('a_travailler', 'en_cours', 'en_progression', 'acquis', 'a_reevaluer'));
ALTER TABLE public.education_objectifs ADD COLUMN IF NOT EXISTS prioritaire BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.education_objectifs ADD COLUMN IF NOT EXISTS difficultes TEXT;

-- 2. Comptes rendus de séance (education_progression) : brouillon / finalisé
--    (« Comptes rendus à finaliser » du tableau de bord), séance d'origine,
--    type, lieu, durée, objectifs travaillés, comportements, difficultés,
--    prochaine étape, profil pro (multi-profils).
ALTER TABLE public.education_progression ADD COLUMN IF NOT EXISTS statut TEXT NOT NULL DEFAULT 'finalise';
DO $$ BEGIN
  ALTER TABLE public.education_progression ADD CONSTRAINT education_progression_statut_check
    CHECK (statut IN ('brouillon', 'finalise'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
ALTER TABLE public.education_progression ADD COLUMN IF NOT EXISTS pro_profile_id UUID;
ALTER TABLE public.education_progression ADD COLUMN IF NOT EXISTS rdv_id UUID;
ALTER TABLE public.education_progression ADD COLUMN IF NOT EXISTS type_seance TEXT;
ALTER TABLE public.education_progression ADD COLUMN IF NOT EXISTS lieu TEXT;
ALTER TABLE public.education_progression ADD COLUMN IF NOT EXISTS duree_minutes INTEGER;
ALTER TABLE public.education_progression ADD COLUMN IF NOT EXISTS objectifs_travailles JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.education_progression ADD COLUMN IF NOT EXISTS comportements TEXT;
ALTER TABLE public.education_progression ADD COLUMN IF NOT EXISTS difficultes TEXT;
ALTER TABLE public.education_progression ADD COLUMN IF NOT EXISTS prochaine_etape TEXT;
ALTER TABLE public.education_progression ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();
CREATE INDEX IF NOT EXISTS education_progression_rdv_idx ON public.education_progression (rdv_id) WHERE rdv_id IS NOT NULL;

NOTIFY pgrst, 'reload schema';
