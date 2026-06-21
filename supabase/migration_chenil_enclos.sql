-- Table des enclos/boxes du chenil (association ou élevage)
CREATE TABLE IF NOT EXISTS enclos_chenil (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  uid_eleveur    TEXT NOT NULL,
  is_association BOOLEAN DEFAULT false,
  nom            TEXT NOT NULL,
  type           TEXT DEFAULT 'box',        -- 'box', 'enclos', 'chatterie', 'cage'
  capacite       INTEGER DEFAULT 1,
  dernier_nettoyage DATE,
  notes          TEXT,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at     TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE enclos_chenil ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Propriétaire enclos" ON enclos_chenil
  USING (uid_eleveur = auth.uid()::text)
  WITH CHECK (uid_eleveur = auth.uid()::text);

-- Champ sur animaux pour assigner un enclos
ALTER TABLE animaux ADD COLUMN IF NOT EXISTS enclos_id UUID REFERENCES enclos_chenil(id) ON DELETE SET NULL;
