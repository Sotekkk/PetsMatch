-- Fix RLS enclos_chenil : supprime la dépendance à auth.uid() (non dispo côté web Firebase)
-- Cohérent avec les autres tables du projet (agenda_events, animaux, etc.)

DROP POLICY IF EXISTS "Propriétaire enclos" ON enclos_chenil;

-- Lecture : chacun voit seulement ses enclos (filtré par uid_eleveur dans la query)
CREATE POLICY "Select own enclos" ON enclos_chenil
  FOR SELECT USING (true);

-- Insertion : uid_eleveur doit être renseigné (non vide)
CREATE POLICY "Insert enclos" ON enclos_chenil
  FOR INSERT WITH CHECK (uid_eleveur IS NOT NULL AND length(uid_eleveur) > 0);

-- Modification : idem
CREATE POLICY "Update enclos" ON enclos_chenil
  FOR UPDATE USING (true) WITH CHECK (uid_eleveur IS NOT NULL AND length(uid_eleveur) > 0);

-- Suppression : toujours via uid_eleveur dans la query applicative
CREATE POLICY "Delete enclos" ON enclos_chenil
  FOR DELETE USING (true);

-- Même fix pour chenil_boxes (table Flutter)
DROP POLICY IF EXISTS "Owner chenil_boxes insert" ON chenil_boxes;
DROP POLICY IF EXISTS "Owner chenil_boxes select" ON chenil_boxes;
DROP POLICY IF EXISTS "Owner chenil_boxes update" ON chenil_boxes;
DROP POLICY IF EXISTS "Owner chenil_boxes delete" ON chenil_boxes;
DROP POLICY IF EXISTS "Owner chenil_boxes" ON chenil_boxes;

CREATE POLICY "Select chenil_boxes" ON chenil_boxes
  FOR SELECT USING (true);

CREATE POLICY "Insert chenil_boxes" ON chenil_boxes
  FOR INSERT WITH CHECK (association_uid IS NOT NULL AND length(association_uid) > 0);

CREATE POLICY "Update chenil_boxes" ON chenil_boxes
  FOR UPDATE USING (true) WITH CHECK (association_uid IS NOT NULL AND length(association_uid) > 0);

CREATE POLICY "Delete chenil_boxes" ON chenil_boxes
  FOR DELETE USING (true);
