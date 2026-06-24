-- ============================================================
-- Migration : Promenades — espèce, races, filtre géographique
-- Date      : 2026-06-23
-- ============================================================

ALTER TABLE promenades
  ADD COLUMN IF NOT EXISTS espece       TEXT DEFAULT 'Toutes',
  ADD COLUMN IF NOT EXISTS toutes_races BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS races        TEXT,
  ADD COLUMN IF NOT EXISTS departement  TEXT,
  ADD COLUMN IF NOT EXISTS region       TEXT;

CREATE INDEX IF NOT EXISTS idx_promenades_espece ON promenades (espece);
CREATE INDEX IF NOT EXISTS idx_promenades_dept   ON promenades (departement);
