-- ============================================================
-- PetsMatch — Toiletteur : employés enrichis (fonctionnalité Premium)
-- Colonnes ajoutées sur la table `employes` générique (réutilisée telle
-- quelle pour l'invitation/permissions, cf. session précédente) +
-- nouvelle table employe_conges.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE employes
  ADD COLUMN IF NOT EXISTS couleur_planning TEXT DEFAULT '#FFB74D',
  ADD COLUMN IF NOT EXISTS competences      JSONB DEFAULT '[]'::jsonb, -- types de prestations autorisées
  ADD COLUMN IF NOT EXISTS horaires         JSONB DEFAULT '{}'::jsonb; -- {"lundi": {"debut":"09:00","fin":"18:00"}, ...}

CREATE TABLE IF NOT EXISTS employe_conges (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  employe_id  BIGINT NOT NULL REFERENCES employes(id) ON DELETE CASCADE,
  date_debut  DATE NOT NULL,
  date_fin    DATE NOT NULL,
  motif       TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_employe_conges_employe ON employe_conges(employe_id);
CREATE INDEX IF NOT EXISTS idx_employe_conges_dates ON employe_conges(date_debut, date_fin);

ALTER TABLE employe_conges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "employe_conges_all" ON employe_conges;
CREATE POLICY "employe_conges_all" ON employe_conges FOR ALL USING (true);
