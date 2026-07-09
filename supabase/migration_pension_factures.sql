-- ============================================================
-- PetsMatch — Pension : alertes facturation (Phase 2, item 2/4)
-- La facturation existante (registre_pension_page.dart) générait un PDF
-- à la volée sans jamais rien persister — impossible de savoir quel
-- séjour est facturé ou quel client est débiteur. Cette table trace
-- chaque facture envoyée et son statut de paiement.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS pension_factures (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid          TEXT NOT NULL,
  pro_profile_id   UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  entree_id        UUID NOT NULL,
  numero           TEXT NOT NULL,
  animal_nom       TEXT,
  proprietaire_nom TEXT,
  proprietaire_uid TEXT,
  montant          NUMERIC NOT NULL DEFAULT 0,
  pdf_url          TEXT,
  statut           TEXT NOT NULL DEFAULT 'envoyee', -- envoyee / payee
  date_envoi       TIMESTAMPTZ NOT NULL DEFAULT now(),
  date_paiement    TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pension_factures_pro ON pension_factures(pro_uid, pro_profile_id);
CREATE INDEX IF NOT EXISTS idx_pension_factures_entree ON pension_factures(entree_id);
CREATE INDEX IF NOT EXISTS idx_pension_factures_statut ON pension_factures(statut);

ALTER TABLE pension_factures ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pension_factures_all" ON pension_factures;
CREATE POLICY "pension_factures_all" ON pension_factures FOR ALL USING (true);
