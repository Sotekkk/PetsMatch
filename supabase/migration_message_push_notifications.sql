-- Migration : notifications push pour nouveaux messages
-- Déclencheur sur messages INSERT → insère dans notifications → webhook → Edge Function FCM

-- Activer pg_net si pas déjà actif (nécessaire pour appeler l'Edge Function directement)
-- CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION notify_new_message()
RETURNS TRIGGER AS $$
DECLARE
  conv_row     RECORD;
  user_row     RECORD;
  sender_name  TEXT;
  msg_preview  TEXT;
  participant  TEXT;
BEGIN
  -- Récupérer conversation + participants_info
  SELECT participants, participants_info
  INTO conv_row
  FROM conversations
  WHERE id = NEW.conversation_id;

  IF NOT FOUND THEN RETURN NEW; END IF;

  -- 1. Essayer participants_info d'abord
  sender_name := (conv_row.participants_info -> NEW.sender_id ->> 'name');

  -- 2. Fallback sur la table users si vide
  IF sender_name IS NULL OR sender_name = '' THEN
    SELECT firstname, lastname, name_elevage, is_elevage
    INTO user_row
    FROM users
    WHERE uid = NEW.sender_id
    LIMIT 1;

    IF FOUND THEN
      IF user_row.is_elevage = true AND user_row.name_elevage IS NOT NULL AND user_row.name_elevage <> '' THEN
        sender_name := user_row.name_elevage;
      ELSE
        sender_name := TRIM(COALESCE(user_row.firstname, '') || ' ' || COALESCE(user_row.lastname, ''));
      END IF;
    END IF;
  END IF;

  sender_name := NULLIF(TRIM(sender_name), '');
  IF sender_name IS NULL THEN sender_name := 'Nouveau message'; END IF;

  -- Aperçu du message (80 chars max)
  msg_preview := CASE
    WHEN NEW.msg_type = 'image'    THEN '📷 Photo'
    WHEN NEW.msg_type = 'location' THEN '📍 Position partagée'
    WHEN NEW.text IS NOT NULL      THEN LEFT(NEW.text, 80)
    ELSE 'Nouveau message'
  END;

  -- Une notification par destinataire (hors expéditeur)
  FOR participant IN
    SELECT jsonb_array_elements_text(conv_row.participants)
  LOOP
    IF participant <> NEW.sender_id THEN
      INSERT INTO notifications (uid, type, title, body, data, read)
      VALUES (
        participant,
        'message',
        sender_name,
        msg_preview,
        jsonb_build_object(
          'conversation_id', NEW.conversation_id,
          'sender_id',       NEW.sender_id,
          'type',            'message'
        ),
        false
      );
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Remplace l'ancien trigger s'il existe
DROP TRIGGER IF EXISTS trg_notify_new_message ON messages;
CREATE TRIGGER trg_notify_new_message
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION notify_new_message();
