-- ─────────────────────────────────────────────────────────────────────────────
-- Suivi éducateur/comportementaliste : coordonnées du propriétaire + partage
-- pour les familles sans compte PetsMatch.
-- ─────────────────────────────────────────────────────────────────────────────

-- Correction manuelle des coordonnées du propriétaire par le pro (même
-- principe que animaux.acquereur_contact_manuel côté cession) : pertinent
-- uniquement quand le propriétaire n'a pas de compte PetsMatch actif.
ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS proprietaire_contact_manuel JSONB;

-- Lien de suivi éducatif en lecture seule pour une famille sans compte
-- (plan de travail, exercices, comptes rendus). Distinct de `partage_animal`
-- (fiche générale, créé par le propriétaire) : ici c'est l'éducateur qui
-- génère le lien.
CREATE TABLE IF NOT EXISTS partage_suivi_education (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  animal_id      TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  pro_uid        TEXT NOT NULL,
  pro_profile_id UUID,
  token          TEXT UNIQUE NOT NULL DEFAULT gen_random_uuid()::TEXT,
  expire_at      TIMESTAMPTZ NOT NULL,
  actif          BOOLEAN NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_partage_suivi_education_token  ON partage_suivi_education(token);
CREATE INDEX IF NOT EXISTS idx_partage_suivi_education_animal ON partage_suivi_education(animal_id);

ALTER TABLE partage_suivi_education ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "partage_suivi_education_all" ON partage_suivi_education;
CREATE POLICY "partage_suivi_education_all" ON partage_suivi_education FOR ALL USING (true) WITH CHECK (true);
