-- Fiche éducative : motif de l'accompagnement saisi directement depuis la
-- Synthèse (sans passer par un bilan). Un motif par (profil éducateur, animal).
-- Le motif d'un bilan reste proposé par défaut tant qu'aucun n'est saisi ici.
-- Même modèle d'accès que education_objectifs. Idempotent.
CREATE TABLE IF NOT EXISTS public.education_suivis (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid         TEXT NOT NULL,
  pro_profile_id  UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  animal_id       TEXT NOT NULL,
  motif           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (pro_profile_id, animal_id)
);

ALTER TABLE public.education_suivis ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "education_suivis_all" ON public.education_suivis;
CREATE POLICY "education_suivis_all" ON public.education_suivis
  FOR ALL USING (true) WITH CHECK (true);

NOTIFY pgrst, 'reload schema';
