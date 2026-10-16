-- « Récupérer mon animal » : l'acquéreur d'un animal cédé à un particulier
-- sans compte (fiche d'élevage, ex. import I-CAD) récupère la fiche en
-- créant son compte. Rattachement direct si son e-mail / téléphone
-- correspond à l'acquéreur enregistré, ou par invitation de l'éleveur ;
-- sinon demande validée par l'éleveur (ici). Toute la logique est côté
-- serveur (/api/animaux/recuperer, service role). Idempotent.
CREATE TABLE IF NOT EXISTS public.animal_recuperations (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  animal_id             TEXT NOT NULL REFERENCES public.animaux(id) ON DELETE CASCADE,
  demandeur_uid         TEXT NOT NULL,
  demandeur_profile_id  UUID,
  eleveur_uid           TEXT NOT NULL,
  message               TEXT,
  statut                TEXT NOT NULL DEFAULT 'en_attente' CHECK (statut IN ('en_attente', 'acceptee', 'refusee')),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_at            TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_animal_recup_eleveur ON public.animal_recuperations (eleveur_uid, statut);
CREATE UNIQUE INDEX IF NOT EXISTS idx_animal_recup_unique_attente
  ON public.animal_recuperations (animal_id, demandeur_uid) WHERE statut = 'en_attente';

ALTER TABLE public.animal_recuperations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "animal_recup_lecture" ON public.animal_recuperations;
CREATE POLICY "animal_recup_lecture" ON public.animal_recuperations FOR SELECT
  USING ((auth.jwt() ->> 'sub') IN (demandeur_uid, eleveur_uid));

NOTIFY pgrst, 'reload schema';
