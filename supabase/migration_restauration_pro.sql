-- Migration: Profil Pro Hébergement/Restauration

-- 1. Colonnes restauration dans user_profiles
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS type_restauration    TEXT,          -- hotel, restaurant, cafe, gite, camping, bar, fast_food, boulangerie, hebergement_insolite, villa_location
  ADD COLUMN IF NOT EXISTS conditions_animaux   TEXT,
  ADD COLUMN IF NOT EXISTS equipements_animaux  JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS capacite_animaux     INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS adresse_pro          TEXT,          -- adresse saisie via Places API
  ADD COLUMN IF NOT EXISTS lat_pro              DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS lng_pro              DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS rue_pro              TEXT,
  ADD COLUMN IF NOT EXISTS cp_pro               TEXT,
  ADD COLUMN IF NOT EXISTS ville_pro            TEXT;

-- 2. Colonnes stats sur petfriendly_places
ALTER TABLE petfriendly_places
  ADD COLUMN IF NOT EXISTS vue_count    INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS vue_semaine  INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS vue_mois     INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS note_moyenne NUMERIC(3,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS nb_avis      INTEGER DEFAULT 0;

-- 3. Table de tracking des vues (une ligne par visite)
CREATE TABLE IF NOT EXISTS place_vues (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  place_id   UUID        NOT NULL REFERENCES petfriendly_places(id) ON DELETE CASCADE,
  user_uid   TEXT,
  session_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pv_place   ON place_vues (place_id);
CREATE INDEX IF NOT EXISTS idx_pv_created ON place_vues (created_at);

ALTER TABLE place_vues ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pv_all" ON place_vues;
CREATE POLICY "pv_all" ON place_vues FOR ALL USING (true);

-- 4. Trigger: incrémenter vue_count à chaque INSERT dans place_vues
CREATE OR REPLACE FUNCTION fn_increment_place_vue()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE petfriendly_places SET vue_count = vue_count + 1 WHERE id = NEW.place_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_increment_place_vue ON place_vues;
CREATE TRIGGER trg_increment_place_vue
  AFTER INSERT ON place_vues
  FOR EACH ROW EXECUTE FUNCTION fn_increment_place_vue();

-- 5. Trigger: notifier le pro quand un avis est posté
CREATE OR REPLACE FUNCTION fn_notify_new_review()
RETURNS TRIGGER AS $$
DECLARE
  pro_uid   TEXT;
  place_nom TEXT;
BEGIN
  SELECT uid_pro, nom INTO pro_uid, place_nom
  FROM petfriendly_places WHERE id = NEW.place_id;
  IF pro_uid IS NULL OR pro_uid = NEW.user_uid THEN RETURN NEW; END IF;

  INSERT INTO notifications (uid, type, title, body, data) VALUES (
    pro_uid, 'new_review',
    '⭐ Nouvel avis',
    'Vous avez reçu un avis sur « ' || COALESCE(place_nom, 'votre établissement') || ' »',
    jsonb_build_object(
      'place_id',  NEW.place_id,
      'review_id', NEW.id,
      'type',      'new_review'
    )
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_new_review ON petfriendly_reviews;
CREATE TRIGGER trg_notify_new_review
  AFTER INSERT ON petfriendly_reviews
  FOR EACH ROW EXECUTE FUNCTION fn_notify_new_review();

-- 6. Trigger: mettre à jour note_moyenne et nb_avis
CREATE OR REPLACE FUNCTION fn_update_place_rating()
RETURNS TRIGGER AS $$
DECLARE
  pid UUID := COALESCE(NEW.place_id, OLD.place_id);
BEGIN
  UPDATE petfriendly_places SET
    nb_avis      = (SELECT COUNT(*) FROM petfriendly_reviews WHERE place_id = pid),
    note_moyenne = COALESCE((SELECT AVG(note) FROM petfriendly_reviews WHERE place_id = pid), 0)
  WHERE id = pid;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_place_rating ON petfriendly_reviews;
CREATE TRIGGER trg_update_place_rating
  AFTER INSERT OR UPDATE OR DELETE ON petfriendly_reviews
  FOR EACH ROW EXECUTE FUNCTION fn_update_place_rating();

-- 7. Trigger: notifier le pro aux paliers de vues (100, 500, 1000, 5000, 10000)
CREATE OR REPLACE FUNCTION fn_notify_vue_milestone()
RETURNS TRIGGER AS $$
DECLARE
  pro_uid   TEXT;
  place_nom TEXT;
BEGIN
  IF NEW.vue_count = OLD.vue_count THEN RETURN NEW; END IF;
  IF NEW.vue_count NOT IN (100, 500, 1000, 5000, 10000) THEN RETURN NEW; END IF;

  SELECT uid_pro, nom INTO pro_uid, place_nom FROM petfriendly_places WHERE id = NEW.id;
  IF pro_uid IS NULL THEN RETURN NEW; END IF;

  INSERT INTO notifications (uid, type, title, body, data) VALUES (
    pro_uid, 'vue_milestone',
    '👀 ' || NEW.vue_count || ' vues !',
    '« ' || COALESCE(place_nom, 'Votre établissement') || ' » a atteint ' || NEW.vue_count || ' vues !',
    jsonb_build_object(
      'place_id',  NEW.id,
      'vue_count', NEW.vue_count,
      'type',      'vue_milestone'
    )
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_vue_milestone ON petfriendly_places;
CREATE TRIGGER trg_notify_vue_milestone
  AFTER UPDATE OF vue_count ON petfriendly_places
  FOR EACH ROW EXECUTE FUNCTION fn_notify_vue_milestone();

-- 8. RLS sur petfriendly_places (si pas encore actif)
ALTER TABLE petfriendly_places ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "pfp_all" ON petfriendly_places;
CREATE POLICY "pfp_all" ON petfriendly_places FOR ALL USING (true);
