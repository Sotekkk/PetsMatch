-- ============================================================
-- PetsMatch — Toiletteur : facturation
-- Montant simple (pas d'acompte/solde demandé pour ce module,
-- contrairement au photographe), dérivée de migration_taxi_factures.sql.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS toilettage_factures (
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

CREATE INDEX IF NOT EXISTS idx_toilettage_factures_pro ON toilettage_factures(pro_uid, pro_profile_id);
CREATE INDEX IF NOT EXISTS idx_toilettage_factures_client ON toilettage_factures(client_uid, client_profile_id);
CREATE INDEX IF NOT EXISTS idx_toilettage_factures_rdv ON toilettage_factures(rdv_id);
CREATE INDEX IF NOT EXISTS idx_toilettage_factures_statut ON toilettage_factures(statut);

ALTER TABLE toilettage_factures ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "toilettage_factures_all" ON toilettage_factures;
CREATE POLICY "toilettage_factures_all" ON toilettage_factures FOR ALL USING (true);
