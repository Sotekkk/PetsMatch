-- Migration : Certificat d'Engagement et d'Information
-- Loi n° 2021-1539 du 30 novembre 2021 — Art. L214-8 Code Rural

CREATE TABLE IF NOT EXISTS public.certificats_engagement (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  animal_id                 TEXT NOT NULL,
  cedant_uid                TEXT NOT NULL,
  acquereur_uid             TEXT,
  acquereur_nom             TEXT,
  acquereur_prenom          TEXT,
  acquereur_adresse         TEXT,
  acquereur_email           TEXT NOT NULL,
  acquereur_telephone       TEXT,
  espece                    TEXT NOT NULL,
  race                      TEXT,
  nom_animal                TEXT,
  date_naissance_animal     DATE,
  num_identification        TEXT,
  modalite_cession          TEXT NOT NULL DEFAULT 'vente',  -- vente / gratuit / adoption
  prix                      NUMERIC,
  date_remise               TIMESTAMPTZ NOT NULL DEFAULT now(),
  date_limite_signature     TIMESTAMPTZ,  -- date_remise + 7j pour chien/chat (calculé à l'insert)
  date_signature_acquereur  TIMESTAMPTZ,
  statut                    TEXT NOT NULL DEFAULT 'envoye'
                            CHECK (statut IN ('envoye','lu','signe','refuse')),
  token_signature           TEXT UNIQUE DEFAULT gen_random_uuid()::TEXT,
  pdf_url                   TEXT,
  notes                     TEXT,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cert_cedant  ON public.certificats_engagement(cedant_uid);
CREATE INDEX IF NOT EXISTS idx_cert_animal  ON public.certificats_engagement(animal_id);
CREATE INDEX IF NOT EXISTS idx_cert_token   ON public.certificats_engagement(token_signature);
CREATE INDEX IF NOT EXISTS idx_cert_statut  ON public.certificats_engagement(statut);

-- RLS
ALTER TABLE public.certificats_engagement ENABLE ROW LEVEL SECURITY;

-- Le cédant peut tout faire sur ses certificats
CREATE POLICY "cedant_all" ON public.certificats_engagement
  FOR ALL USING (true) WITH CHECK (true);
