-- ============================================================
-- PetsMatch — Photographe animalier : facturation acompte + solde
-- Sur le modèle de migration_taxi_factures.sql, avec deux montants
-- (acompte/solde) et un statut détaillé plutôt qu'un montant unique —
-- décision validée avec l'utilisatrice (une facture, 2 montants).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS photographe_factures (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid               TEXT NOT NULL,
  pro_profile_id        UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  rdv_id                UUID REFERENCES rdv(id) ON DELETE SET NULL,
  client_uid            TEXT,
  client_profile_id     UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  numero                TEXT NOT NULL,
  client_nom            TEXT,
  montant_acompte       NUMERIC NOT NULL DEFAULT 0,
  montant_solde         NUMERIC NOT NULL DEFAULT 0,
  montant_total         NUMERIC NOT NULL DEFAULT 0,
  statut                TEXT NOT NULL DEFAULT 'acompte_du',
  -- acompte_du / acompte_paye / solde_du / payee
  pdf_url               TEXT,
  date_envoi            TIMESTAMPTZ NOT NULL DEFAULT now(),
  date_paiement_acompte TIMESTAMPTZ,
  date_paiement_solde   TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_photographe_factures_pro ON photographe_factures(pro_uid, pro_profile_id);
CREATE INDEX IF NOT EXISTS idx_photographe_factures_client ON photographe_factures(client_uid, client_profile_id);
CREATE INDEX IF NOT EXISTS idx_photographe_factures_rdv ON photographe_factures(rdv_id);
CREATE INDEX IF NOT EXISTS idx_photographe_factures_statut ON photographe_factures(statut);

ALTER TABLE photographe_factures ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "photographe_factures_all" ON photographe_factures;
CREATE POLICY "photographe_factures_all" ON photographe_factures FOR ALL USING (true);
