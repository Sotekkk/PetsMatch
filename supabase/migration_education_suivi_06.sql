-- ============================================================
-- PetsMatch — Éducateur : outil de suivi partagé (Phase 6)
-- Suivi de forfait : solde de séances d'un forfait souscrit par une famille.
-- Souscription manuelle par l'éducateur OU auto à la signature d'un devis.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS forfaits_souscrits (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  forfait_id           UUID REFERENCES forfaits_education(id) ON DELETE SET NULL,
  pro_uid              TEXT NOT NULL,
  pro_profile_id       UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  client_uid           TEXT,
  client_profile_id    UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  animal_id            TEXT,
  nom_snapshot         TEXT NOT NULL,
  nb_seances_total     INTEGER NOT NULL DEFAULT 1,
  prix_snapshot        NUMERIC,
  nb_seances_utilisees INTEGER NOT NULL DEFAULT 0,
  devis_id             UUID,
  statut               TEXT NOT NULL DEFAULT 'actif'
                         CHECK (statut IN ('actif', 'termine', 'annule')),
  souscrit_le          TIMESTAMPTZ NOT NULL DEFAULT now(),
  termine_le           TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_forfaits_souscrits_animal
  ON forfaits_souscrits (animal_id);
CREATE INDEX IF NOT EXISTS idx_forfaits_souscrits_pro
  ON forfaits_souscrits (pro_uid, pro_profile_id);

ALTER TABLE forfaits_souscrits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "forfaits_souscrits_all" ON forfaits_souscrits;
CREATE POLICY "forfaits_souscrits_all" ON forfaits_souscrits
  FOR ALL USING (true) WITH CHECK (true);

-- Lien séance -> forfait imputé
ALTER TABLE education_progression
  ADD COLUMN IF NOT EXISTS forfait_souscrit_id UUID;
