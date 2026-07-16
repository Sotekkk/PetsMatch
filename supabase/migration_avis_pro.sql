-- ============================================================
-- PetsMatch — Système d'avis générique pour les profils pro
-- (`avis_pro`), pensé pour taxi_animalier et réutilisable tel quel par
-- les futurs modules photographe/toiletteur — pas de table dédiée par
-- profession, contrairement à petfriendly_reviews (lieux).
-- Scoping cross-profil dès la création : pro_uid+pro_profile_id ET
-- client_uid+client_profile_id.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS avis_pro (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid           TEXT NOT NULL,
  pro_profile_id    UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  client_uid        TEXT NOT NULL,
  client_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  note              SMALLINT NOT NULL CHECK (note BETWEEN 1 AND 5),
  commentaire       TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_avis_pro_pro ON avis_pro(pro_uid, pro_profile_id);
CREATE INDEX IF NOT EXISTS idx_avis_pro_client ON avis_pro(client_uid, client_profile_id);

-- Un seul avis par client et par profil pro (quand le profil est identifié).
CREATE UNIQUE INDEX IF NOT EXISTS ux_avis_pro_client_profile
  ON avis_pro(pro_profile_id, client_uid) WHERE pro_profile_id IS NOT NULL;

ALTER TABLE avis_pro ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "avis_pro_all" ON avis_pro;
CREATE POLICY "avis_pro_all" ON avis_pro FOR ALL USING (true);

-- Stats dénormalisées sur user_profiles (même principe que
-- petfriendly_places.note_moyenne/nb_avis — voir migration_restauration_pro.sql).
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS note_moyenne NUMERIC(3,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS nb_avis      INTEGER DEFAULT 0;

CREATE OR REPLACE FUNCTION fn_update_pro_rating()
RETURNS TRIGGER AS $$
DECLARE
  pid UUID := COALESCE(NEW.pro_profile_id, OLD.pro_profile_id);
BEGIN
  IF pid IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;
  UPDATE user_profiles SET
    nb_avis      = (SELECT COUNT(*) FROM avis_pro WHERE pro_profile_id = pid),
    note_moyenne = COALESCE((SELECT AVG(note) FROM avis_pro WHERE pro_profile_id = pid), 0)
  WHERE id = pid;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_pro_rating ON avis_pro;
CREATE TRIGGER trg_update_pro_rating
  AFTER INSERT OR UPDATE OR DELETE ON avis_pro
  FOR EACH ROW EXECUTE FUNCTION fn_update_pro_rating();

-- Notifier le pro à la réception d'un nouvel avis.
CREATE OR REPLACE FUNCTION fn_notify_new_avis_pro()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.pro_uid IS NULL OR NEW.pro_uid = NEW.client_uid THEN RETURN NEW; END IF;
  INSERT INTO notifications (uid, type, title, body, data) VALUES (
    NEW.pro_uid, 'new_avis_pro',
    '⭐ Nouvel avis',
    'Vous avez reçu un nouvel avis client.',
    jsonb_build_object('avis_id', NEW.id, 'type', 'new_avis_pro')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_new_avis_pro ON avis_pro;
CREATE TRIGGER trg_notify_new_avis_pro
  AFTER INSERT ON avis_pro
  FOR EACH ROW EXECUTE FUNCTION fn_notify_new_avis_pro();
