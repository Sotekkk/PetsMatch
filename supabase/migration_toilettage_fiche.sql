-- Toilettage — fiche animal métier (étape 2 de la refonte toiletteur).
-- 1. fiches_toilettage (une par animal × salon) : consignes PERMANENTES,
--    observations professionnelles. Les allergies déclarées par le
--    propriétaire restent dans son carnet (table allergies) et sont
--    affichées à part.
-- 2. seances_toilettage : fiche technique d'UNE prestation (rattachée au
--    rdv) — travail effectué, préférences appliquées, comportement,
--    compte rendu court partagé ou non avec le propriétaire. Une ligne par
--    rendez-vous : l'historique n'est jamais écrasé. Photos avant / après :
--    fiches_toilettage_photos (rdv_id), inchangé. Idempotent.
ALTER TABLE public.fiches_toilettage ADD COLUMN IF NOT EXISTS type_poil TEXT;
ALTER TABLE public.fiches_toilettage ADD COLUMN IF NOT EXISTS particularites_pelage TEXT;
ALTER TABLE public.fiches_toilettage ADD COLUMN IF NOT EXISTS longueur_coupe TEXT;
ALTER TABLE public.fiches_toilettage ADD COLUMN IF NOT EXISTS zones_sensibles TEXT;
ALTER TABLE public.fiches_toilettage ADD COLUMN IF NOT EXISTS tolerance_sechoir TEXT;
ALTER TABLE public.fiches_toilettage ADD COLUMN IF NOT EXISTS comportement_manipulation TEXT;
ALTER TABLE public.fiches_toilettage ADD COLUMN IF NOT EXISTS produits_a_eviter TEXT;
ALTER TABLE public.fiches_toilettage ADD COLUMN IF NOT EXISTS demandes_specifiques TEXT;
ALTER TABLE public.fiches_toilettage ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

CREATE TABLE IF NOT EXISTS public.seances_toilettage (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rdv_id                UUID UNIQUE,
  fiche_id              UUID,
  animal_id             TEXT NOT NULL,
  pro_uid               TEXT NOT NULL,
  pro_profile_id        UUID,
  employe_id            UUID,
  date_seance           DATE NOT NULL DEFAULT CURRENT_DATE,
  duree_minutes         INTEGER,
  travaux               JSONB NOT NULL DEFAULT '[]'::jsonb,
  longueur_coupe        TEXT,
  zones                 TEXT,
  finition              TEXT,
  produits              TEXT,
  cooperation           TEXT,
  sensibilites          TEXT,
  difficultes           TEXT,
  precautions           TEXT,
  observations          TEXT,
  compte_rendu          TEXT,
  partage_proprietaire  BOOLEAN NOT NULL DEFAULT false,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS seances_toilettage_animal_idx ON public.seances_toilettage (animal_id, date_seance DESC);
CREATE INDEX IF NOT EXISTS seances_toilettage_pro_idx ON public.seances_toilettage (pro_profile_id);

-- Même modèle d'accès que fiches_toilettage (migration_rls_tighten_toilettage) :
-- le salon (pro_uid) ou un cogérant actif. Le propriétaire de l'animal lit
-- uniquement les comptes rendus que le salon a choisi de partager.
ALTER TABLE public.seances_toilettage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "seances_toilettage_all" ON public.seances_toilettage;
DROP POLICY IF EXISTS "seances_toilettage_pro_or_cogerant" ON public.seances_toilettage;
CREATE POLICY "seances_toilettage_pro_or_cogerant" ON public.seances_toilettage
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = seances_toilettage.pro_uid
      AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = seances_toilettage.pro_uid
      AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  );
DROP POLICY IF EXISTS "seances_toilettage_proprietaire_partage" ON public.seances_toilettage;
CREATE POLICY "seances_toilettage_proprietaire_partage" ON public.seances_toilettage
  FOR SELECT USING (
    partage_proprietaire
    AND EXISTS (SELECT 1 FROM animaux_proprietes ap WHERE ap.animal_id = seances_toilettage.animal_id
      AND ap.uid_proprio = (auth.jwt() ->> 'sub') AND ap.date_fin IS NULL)
  );

NOTIFY pgrst, 'reload schema';
