-- Colonne is_association sur animaux (séparation profil éleveur / association)
ALTER TABLE animaux ADD COLUMN IF NOT EXISTS is_association BOOLEAN DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_animaux_is_association ON animaux(is_association);

-- RLS chenil_boxes : politique séparée pour SELECT public (lecture seule) + INSERT/UPDATE/DELETE owner
-- Au cas où la politique précédente ne couvre pas correctement le SELECT depuis l'app
DROP POLICY IF EXISTS "Owner chenil_boxes" ON chenil_boxes;
DROP POLICY IF EXISTS "Public read chenil_boxes" ON chenil_boxes;

CREATE POLICY "Owner chenil_boxes insert" ON chenil_boxes
  FOR INSERT WITH CHECK (association_uid = auth.uid()::text);

CREATE POLICY "Owner chenil_boxes select" ON chenil_boxes
  FOR SELECT USING (association_uid = auth.uid()::text);

CREATE POLICY "Owner chenil_boxes update" ON chenil_boxes
  FOR UPDATE USING (association_uid = auth.uid()::text)
  WITH CHECK (association_uid = auth.uid()::text);

CREATE POLICY "Owner chenil_boxes delete" ON chenil_boxes
  FOR DELETE USING (association_uid = auth.uid()::text);
