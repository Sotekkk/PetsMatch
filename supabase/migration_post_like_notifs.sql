-- Migration: notification quand quelqu'un like un post de groupe

CREATE OR REPLACE FUNCTION notify_post_like()
RETURNS TRIGGER AS $$
DECLARE
  auteur_uid  TEXT;
  groupe_id_v UUID;
  groupe_nom  TEXT;
BEGIN
  SELECT gp.auteur_uid, gp.groupe_id INTO auteur_uid, groupe_id_v
  FROM groupe_posts gp WHERE gp.id = NEW.post_id;

  IF auteur_uid IS NULL THEN RETURN NEW; END IF;
  IF auteur_uid = NEW.user_uid THEN RETURN NEW; END IF; -- pas de notif sur ses propres posts

  SELECT nom INTO groupe_nom FROM groupes WHERE id = groupe_id_v;

  INSERT INTO notifications (uid, type, title, body, data) VALUES (
    auteur_uid,
    'post_like',
    '❤️ Nouveau like',
    'Quelqu''un a aimé votre publication dans « ' || COALESCE(groupe_nom, 'un groupe') || ' »',
    jsonb_build_object(
      'post_id',    NEW.post_id,
      'groupe_id',  groupe_id_v,
      'user_uid',   NEW.user_uid,
      'type',       'post_like'
    )
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_post_like ON groupe_post_likes;
CREATE TRIGGER trg_notify_post_like
  AFTER INSERT ON groupe_post_likes
  FOR EACH ROW
  EXECUTE FUNCTION notify_post_like();
