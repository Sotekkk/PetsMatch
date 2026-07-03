-- ============================================================
-- PetsMatch — Suivi du nettoyage jour par jour des logements pension.
-- Remplace le suivi global (enclos_chenil.dernier_nettoyage) par un
-- historique par jour : présence d'une ligne = logement nettoyé ce
-- jour-là. Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS pension_nettoyages (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  logement_id  UUID NOT NULL REFERENCES enclos_chenil(id) ON DELETE CASCADE,
  uid_eleveur  TEXT NOT NULL,
  date         DATE NOT NULL,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (logement_id, date)
);

CREATE INDEX IF NOT EXISTS idx_pension_nettoyages_logement ON pension_nettoyages(logement_id);

ALTER TABLE pension_nettoyages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select pension_nettoyages" ON pension_nettoyages;
CREATE POLICY "Select pension_nettoyages" ON pension_nettoyages
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Insert pension_nettoyages" ON pension_nettoyages;
CREATE POLICY "Insert pension_nettoyages" ON pension_nettoyages
  FOR INSERT WITH CHECK (uid_eleveur IS NOT NULL AND length(uid_eleveur) > 0);

DROP POLICY IF EXISTS "Delete pension_nettoyages" ON pension_nettoyages;
CREATE POLICY "Delete pension_nettoyages" ON pension_nettoyages
  FOR DELETE USING (true);
