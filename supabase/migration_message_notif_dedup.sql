-- ══════════════════════════════════════════════════════════════════════════
-- Messagerie — notification en double (push + cloche)
-- ══════════════════════════════════════════════════════════════════════════
-- Chaque message créait DEUX lignes `notifications` :
--   1. le trigger trg_notify_new_message (migration_message_push_notifications.sql)
--   2. l'appli elle-même (chatScreen.dart / petfriend_chat_page.dart)
-- → deux pushs sur le téléphone + deux entrées dans la cloche.
--
-- Le site ne crée aucune notif de message (il compte sur le trigger), donc le
-- trigger reste la source UNIQUE ; les inserts côté appli sont supprimés.
-- Le trigger reprend ce que faisait l'appli :
--   • pas de notif si le destinataire a déjà la conversation ouverte
--     (users.active_conversation_id)
--   • titre « Expéditeur · Nom du groupe » pour les groupes PetFriends
--   • aperçu lisible pour les fiches animal / demandes de dépannage
--     (au lieu du JSON brut)
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION notify_new_message()
RETURNS TRIGGER AS $$
DECLARE
  conv_row     RECORD;
  user_row     RECORD;
  sender_name  TEXT;
  notif_title  TEXT;
  msg_preview  TEXT;
  participant  TEXT;
  active_conv  TEXT;
BEGIN
  SELECT participants, participants_info, type, nom
  INTO conv_row
  FROM conversations
  WHERE id = NEW.conversation_id;

  IF NOT FOUND THEN RETURN NEW; END IF;

  -- 1. participants_info d'abord
  sender_name := (conv_row.participants_info -> NEW.sender_id ->> 'name');

  -- 2. Fallback sur la table users
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

  notif_title := sender_name;
  IF conv_row.type = 'groupe' AND COALESCE(conv_row.nom, '') <> '' THEN
    notif_title := sender_name || ' · ' || conv_row.nom;
  END IF;

  msg_preview := CASE
    WHEN NEW.msg_type = 'image'         THEN '📷 Photo'
    WHEN NEW.msg_type = 'location'      THEN '📍 Position partagée'
    WHEN NEW.msg_type = 'animal_card'   THEN '🐾 Fiche animal'
    WHEN NEW.msg_type = 'garde_request' THEN '🐾 Demande de dépannage'
    WHEN NEW.text IS NOT NULL AND NEW.text <> '' THEN
      CASE WHEN LENGTH(NEW.text) > 80 THEN LEFT(NEW.text, 80) || '…' ELSE NEW.text END
    ELSE 'Nouveau message'
  END;

  FOR participant IN
    SELECT DISTINCT jsonb_array_elements_text(conv_row.participants)
  LOOP
    CONTINUE WHEN participant = NEW.sender_id;

    -- Destinataire déjà dans la conversation → il voit le message en direct
    SELECT active_conversation_id INTO active_conv
    FROM users WHERE uid = participant LIMIT 1;
    CONTINUE WHEN active_conv IS NOT NULL AND active_conv = NEW.conversation_id::text;

    INSERT INTO notifications (uid, type, title, body, data, read)
    VALUES (
      participant,
      'message',
      notif_title,
      msg_preview,
      jsonb_build_object(
        'conversation_id', NEW.conversation_id,
        'sender_id',       NEW.sender_id,
        'type',            'message'
      ),
      false
    );
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_new_message ON messages;
CREATE TRIGGER trg_notify_new_message
  AFTER INSERT ON messages
  FOR EACH ROW
  EXECUTE FUNCTION notify_new_message();
