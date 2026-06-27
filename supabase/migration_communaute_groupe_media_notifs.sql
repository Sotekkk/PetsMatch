-- Migration: groupe avatar/bannière + notifications membres

-- 1. Colonne avatar_url sur groupes (photo de profil du groupe)
ALTER TABLE groupes
  ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- 2. Trigger notification quand quelqu'un rejoint ou demande
CREATE OR REPLACE FUNCTION notify_groupe_join()
RETURNS TRIGGER AS $$
DECLARE
  admin_uid  TEXT;
  groupe_nom TEXT;
BEGIN
  SELECT nom INTO groupe_nom FROM groupes WHERE id = NEW.groupe_id;
  IF groupe_nom IS NULL THEN RETURN NEW; END IF;

  IF NEW.statut = 'pending' THEN
    -- Quelqu'un demande à rejoindre un groupe privé → notifier les admins
    FOR admin_uid IN
      SELECT user_uid FROM groupes_membres
      WHERE groupe_id = NEW.groupe_id AND role = 'admin' AND statut = 'active'
    LOOP
      INSERT INTO notifications (uid, type, title, body, data)
      VALUES (
        admin_uid,
        'groupe_demande',
        '👥 Nouvelle demande',
        'Quelqu''un souhaite rejoindre ' || groupe_nom,
        jsonb_build_object('groupe_id', NEW.groupe_id, 'user_uid', NEW.user_uid, 'type', 'groupe_demande')
      );
    END LOOP;

  ELSIF NEW.statut = 'active' THEN
    IF TG_OP = 'UPDATE' AND OLD.statut = 'pending' THEN
      -- Demande approuvée → notifier le membre accepté
      INSERT INTO notifications (uid, type, title, body, data)
      VALUES (
        NEW.user_uid,
        'groupe_accepte',
        '✅ Demande acceptée',
        'Vous avez été accepté dans « ' || groupe_nom || ' »',
        jsonb_build_object('groupe_id', NEW.groupe_id, 'type', 'groupe_accepte')
      );
    ELSIF TG_OP = 'INSERT' THEN
      -- Rejoindre direct (groupe public) → notifier les admins
      FOR admin_uid IN
        SELECT user_uid FROM groupes_membres
        WHERE groupe_id = NEW.groupe_id AND role = 'admin' AND statut = 'active'
          AND user_uid <> NEW.user_uid
      LOOP
        INSERT INTO notifications (uid, type, title, body, data)
        VALUES (
          admin_uid,
          'groupe_rejoint',
          '👥 Nouveau membre',
          'Un nouveau membre a rejoint « ' || groupe_nom || ' »',
          jsonb_build_object('groupe_id', NEW.groupe_id, 'user_uid', NEW.user_uid, 'type', 'groupe_rejoint')
        );
      END LOOP;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_groupe_join ON groupes_membres;
CREATE TRIGGER trg_notify_groupe_join
  AFTER INSERT OR UPDATE OF statut ON groupes_membres
  FOR EACH ROW
  EXECUTE FUNCTION notify_groupe_join();
