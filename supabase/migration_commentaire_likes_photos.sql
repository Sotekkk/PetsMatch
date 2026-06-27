-- Migration: likes sur commentaires + photo dans commentaires

-- 1. Colonnes sur groupe_post_commentaires
ALTER TABLE groupe_post_commentaires
  ADD COLUMN IF NOT EXISTS like_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS image_url  TEXT;

-- 2. Table des likes de commentaires
CREATE TABLE IF NOT EXISTS groupe_commentaire_likes (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  comment_id UUID        NOT NULL REFERENCES groupe_post_commentaires(id) ON DELETE CASCADE,
  user_uid   TEXT        NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(comment_id, user_uid)
);

CREATE INDEX IF NOT EXISTS idx_gcl_comment ON groupe_commentaire_likes (comment_id);
CREATE INDEX IF NOT EXISTS idx_gcl_user    ON groupe_commentaire_likes (user_uid);

ALTER TABLE groupe_commentaire_likes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "gcl_all" ON groupe_commentaire_likes;
CREATE POLICY "gcl_all" ON groupe_commentaire_likes FOR ALL USING (true);

-- 3. Trigger: notifier l'auteur du commentaire quand quelqu'un like
CREATE OR REPLACE FUNCTION notify_commentaire_like()
RETURNS TRIGGER AS $$
DECLARE
  auteur_uid  TEXT;
  groupe_id_v UUID;
  groupe_nom  TEXT;
BEGIN
  SELECT gc.auteur_uid, gp.groupe_id INTO auteur_uid, groupe_id_v
  FROM groupe_post_commentaires gc
  JOIN groupe_posts gp ON gp.id = gc.post_id
  WHERE gc.id = NEW.comment_id;

  IF auteur_uid IS NULL THEN RETURN NEW; END IF;
  IF auteur_uid = NEW.user_uid THEN RETURN NEW; END IF; -- pas de notif sur son propre commentaire

  SELECT nom INTO groupe_nom FROM groupes WHERE id = groupe_id_v;

  INSERT INTO notifications (uid, type, title, body, data) VALUES (
    auteur_uid,
    'commentaire_like',
    '❤️ Commentaire aimé',
    'Quelqu''un a aimé votre commentaire dans « ' || COALESCE(groupe_nom, 'un groupe') || ' »',
    jsonb_build_object(
      'comment_id', NEW.comment_id,
      'groupe_id',  groupe_id_v,
      'user_uid',   NEW.user_uid,
      'type',       'commentaire_like'
    )
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_commentaire_like ON groupe_commentaire_likes;
CREATE TRIGGER trg_notify_commentaire_like
  AFTER INSERT ON groupe_commentaire_likes
  FOR EACH ROW
  EXECUTE FUNCTION notify_commentaire_like();
