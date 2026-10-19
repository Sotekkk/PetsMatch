-- Pension — réservation de séjour par le client (au lieu d'un rendez-vous) :
-- dates d'arrivée et de départ, animal, message ; demande à accepter par la
-- pension. Si la pension exige un essai (user_profiles.pension_essai_requis)
-- et que c'est le premier séjour de l'animal chez elle, le client propose une
-- date d'essai (une journée) avant le séjour.
-- À l'acceptation (route /api/pension/sejour, service role) : le séjour (et
-- l'essai) sont créés dans pension_entrees (statut en_pension) → planning
-- d'occupation, arrivées / départs du jour. Les demandes restent dans leur
-- table : le registre n'est jamais pollué par des demandes non acceptées.
-- Idempotent.

ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS pension_essai_requis BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS pension_essai_info TEXT;

CREATE TABLE IF NOT EXISTS public.pension_demandes (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid           TEXT NOT NULL,
  pro_profile_id    UUID,
  client_uid        TEXT NOT NULL,
  client_profile_id UUID,
  animal_id         TEXT NOT NULL,
  animal_nom        TEXT,
  espece            TEXT,
  date_arrivee      DATE NOT NULL,
  date_depart       DATE NOT NULL,
  essai_date        DATE,
  message           TEXT,
  statut            TEXT NOT NULL DEFAULT 'demande' CHECK (statut IN ('demande', 'acceptee', 'refusee', 'annulee')),
  motif_refus       TEXT,
  entree_id         UUID,
  essai_entree_id   UUID,
  decide_le         TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS pension_demandes_pro_idx ON public.pension_demandes (pro_profile_id, statut, date_arrivee);
CREATE INDEX IF NOT EXISTS pension_demandes_client_idx ON public.pension_demandes (client_uid, created_at DESC);

-- Lecture : la pension (ou un cogérant actif) et le client. Écritures : serveur.
ALTER TABLE public.pension_demandes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pension_demandes_lecture ON public.pension_demandes;
CREATE POLICY pension_demandes_lecture ON public.pension_demandes FOR SELECT USING (
  (auth.jwt() ->> 'sub') = pro_uid
  OR (auth.jwt() ->> 'sub') = client_uid
  OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = pension_demandes.pro_uid
    AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
);

NOTIFY pgrst, 'reload schema';
