-- ============================================================
-- PetsMatch — Taxi animalier : facturation des courses
-- Sur le modèle de migration_pension_factures.sql, avec en plus le
-- scoping client dès la création (pro_uid/pro_profile_id ET
-- client_uid/client_profile_id) — contrainte cross-profil de ce chantier.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS taxi_factures (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid           TEXT NOT NULL,
  pro_profile_id    UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  rdv_id            UUID REFERENCES rdv(id) ON DELETE SET NULL,
  client_uid        TEXT,
  client_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  numero            TEXT NOT NULL,
  client_nom        TEXT,
  montant           NUMERIC NOT NULL DEFAULT 0,
  pdf_url           TEXT,
  statut            TEXT NOT NULL DEFAULT 'envoyee', -- envoyee / payee
  date_envoi        TIMESTAMPTZ NOT NULL DEFAULT now(),
  date_paiement     TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_taxi_factures_pro ON taxi_factures(pro_uid, pro_profile_id);
CREATE INDEX IF NOT EXISTS idx_taxi_factures_client ON taxi_factures(client_uid, client_profile_id);
CREATE INDEX IF NOT EXISTS idx_taxi_factures_rdv ON taxi_factures(rdv_id);
CREATE INDEX IF NOT EXISTS idx_taxi_factures_statut ON taxi_factures(statut);

ALTER TABLE taxi_factures ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "taxi_factures_all" ON taxi_factures;
CREATE POLICY "taxi_factures_all" ON taxi_factures FOR ALL USING (true);
