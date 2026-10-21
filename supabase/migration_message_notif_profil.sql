-- ══════════════════════════════════════════════════════════════════════════
-- Messagerie multi-profil — la notification d'un message vise le BON profil
-- ══════════════════════════════════════════════════════════════════════════
-- Une conversation relie deux profils précis (pro_profile_id = celui qui l'a
-- ouverte, consumer_profile_id = le destinataire). La notification créée par
-- trg_notify_new_message n'avait pas de profile_id : elle tombait sur le
-- profil principal du destinataire (ex. son profil particulier) alors que la
-- conversation appartient à sa pension.
--   • profile_id = le profil du destinataire dans la conversation (sinon son
--     profil principal) → cloche du bon profil, pastille sur ce profil dans le
--     sélecteur, push suffixé du nom du profil et bascule proposée au toucher
--     (send-push-notification → recipient_profile_id).
--   • data.conversationId en plus de conversation_id (clé lue au toucher du
--     push par l'appli).
--   • updated_at des conversations recalé sur leur dernier message (l'appli
--     écrivait l'heure locale sans fuseau : 2 h d'avance affichées).
-- Idempotent.
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
  dest_profil  UUID;
BEGIN
  SELECT participants, participants_info, type, nom, pro_profile_id, consumer_profile_id
  INTO conv_row
  FROM conversations
  WHERE id = NEW.conversation_id;

  IF NOT FOUND THEN RETURN NEW; END IF;

  sender_name := (conv_row.participants_info -> NEW.sender_id ->> 'name');

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

    SELECT active_conversation_id INTO active_conv
    FROM users WHERE uid = participant LIMIT 1;
    CONTINUE WHEN active_conv IS NOT NULL AND active_conv = NEW.conversation_id::text;

    -- Profil du destinataire dans cette conversation, sinon son profil principal.
    dest_profil := NULL;
    IF conv_row.type IS DISTINCT FROM 'groupe' THEN
      SELECT up.id INTO dest_profil FROM user_profiles up
       WHERE up.uid = participant AND up.id IN (conv_row.pro_profile_id, conv_row.consumer_profile_id)
       LIMIT 1;
    END IF;
    IF dest_profil IS NULL THEN
      SELECT up.id INTO dest_profil FROM user_profiles up
       WHERE up.uid = participant AND up.is_main = true LIMIT 1;
    END IF;

    INSERT INTO notifications (uid, profile_id, type, title, body, data, read)
    VALUES (
      participant,
      dest_profil::text,
      'message',
      notif_title,
      msg_preview,
      jsonb_build_object(
        'conversation_id', NEW.conversation_id,
        'conversationId',  NEW.conversation_id,
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

-- Conversations : heure recalée sur le dernier message (heure locale écrite sans fuseau).
UPDATE conversations c
   SET updated_at = m.dernier
  FROM (SELECT conversation_id, max(created_at) AS dernier FROM messages GROUP BY conversation_id) m
 WHERE m.conversation_id = c.id AND c.updated_at > m.dernier + interval '5 minutes';
