-- Table des boxes/enclos du chenil (association)
CREATE TABLE IF NOT EXISTS chenil_boxes (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  association_uid TEXT NOT NULL,
  nom             TEXT NOT NULL,
  espece          TEXT NOT NULL DEFAULT 'autre',
  capacite        INTEGER NOT NULL DEFAULT 2,
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE chenil_boxes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owner chenil_boxes" ON chenil_boxes;
CREATE POLICY "Owner chenil_boxes" ON chenil_boxes
  USING (association_uid = auth.uid()::text)
  WITH CHECK (association_uid = auth.uid()::text);

CREATE INDEX IF NOT EXISTS idx_chenil_boxes_asso ON chenil_boxes(association_uid);

-- Colonne box_id sur animaux (référence chenil_boxes)
ALTER TABLE animaux ADD COLUMN IF NOT EXISTS box_id UUID REFERENCES chenil_boxes(id) ON DELETE SET NULL;
