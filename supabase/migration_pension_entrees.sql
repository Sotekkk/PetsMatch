-- Table: pension_entrees
-- Registre des entrées/sorties pension (pro)

CREATE TABLE IF NOT EXISTS pension_entrees (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid                TEXT NOT NULL,
  animal_nom             TEXT NOT NULL,
  espece                 TEXT,
  race                   TEXT,
  puce                   TEXT,
  proprietaire_nom       TEXT,
  proprietaire_contact   TEXT,
  date_entree            DATE NOT NULL,
  date_sortie_prevue     DATE,
  date_sortie_effective  DATE,
  statut                 TEXT NOT NULL DEFAULT 'en_pension'
                           CHECK (statut IN ('en_pension', 'sorti')),
  notes                  TEXT,
  created_at             TIMESTAMPTZ DEFAULT NOW()
);

-- Index pour les requêtes par pro
CREATE INDEX IF NOT EXISTS idx_pension_entrees_pro_uid
  ON pension_entrees (pro_uid, date_entree DESC);

-- RLS
ALTER TABLE pension_entrees ENABLE ROW LEVEL SECURITY;

-- Le pro peut voir et modifier ses propres entrées
CREATE POLICY "pro_own_entrees" ON pension_entrees
  FOR ALL USING (pro_uid = auth.uid()::text);
