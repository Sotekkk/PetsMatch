-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 3/N : messagerie (conversations, messages, bloquages,
-- message_reactions)
-- ══════════════════════════════════════════════════════════════════════════
-- Même contexte que les vagues précédentes : (auth.jwt() ->> 'sub') reflète
-- maintenant le vrai uid Firebase connecté (Third-Party Auth actif).
--
-- ⚠️ Point important découvert en préparant cette migration : la messagerie
-- n'a PAS reçu le traitement cogérance cette semaine — message.dart filtre
-- déjà les conversations par participants @> [mon uid] côté app (ligne
-- .filter('participants', 'cs', '["$_uid"]')), donc un cogérant ne voit
-- DÉJÀ PAS les conversations professionnelles de l'élevage qu'il co-gère,
-- même aujourd'hui en RLS permissive. Cette migration REPRODUIT ce
-- comportement existant au niveau base (elle ne l'aggrave pas), mais ne le
-- corrige pas non plus — c'est un gap de fonctionnalité séparé, pas un
-- sujet de sécurité, à traiter à part si besoin.
--
-- Modèle retenu :
--   - conversations : lisible/modifiable/supprimable par qui figure dans
--     `participants` (JSONB). Création : le créateur doit s'inclure lui-même.
--   - messages : lisibles/modifiables/supprimables par un participant de LA
--     CONVERSATION (pas seulement l'auteur du message — nécessaire pour
--     "vider la conversation" et la suppression de conversation entière).
--     Envoi : sender_id doit être soi-même ET on doit être participant.
--   - bloquages : chacun gère uniquement sa propre liste de blocage.
--   - message_reactions : lecture ouverte aux participants de la conversation
--     du message ; ajout/suppression de SA PROPRE réaction uniquement.
--
-- ⚠️ À TESTER après exécution :
--   1. La liste des conversations s'affiche normalement (bulle de messages).
--   2. Ouvrir une conversation, lire les messages, en envoyer un nouveau.
--   3. Bloquer / débloquer un utilisateur.
--   4. Réagir à un message avec un emoji.
--   5. Supprimer un message, puis supprimer une conversation entière.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── conversations ────────────────────────────────────────────────────────
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "conv_all" ON conversations;
DROP POLICY IF EXISTS "conversations_participant_select" ON conversations;
DROP POLICY IF EXISTS "conversations_participant_insert" ON conversations;
DROP POLICY IF EXISTS "conversations_participant_update" ON conversations;
DROP POLICY IF EXISTS "conversations_participant_delete" ON conversations;

CREATE POLICY "conversations_participant_select" ON conversations
  FOR SELECT USING (participants @> to_jsonb((auth.jwt() ->> 'sub')));

CREATE POLICY "conversations_participant_insert" ON conversations
  FOR INSERT WITH CHECK (participants @> to_jsonb((auth.jwt() ->> 'sub')));

CREATE POLICY "conversations_participant_update" ON conversations
  FOR UPDATE USING (participants @> to_jsonb((auth.jwt() ->> 'sub')));

CREATE POLICY "conversations_participant_delete" ON conversations
  FOR DELETE USING (participants @> to_jsonb((auth.jwt() ->> 'sub')));

-- ── messages ─────────────────────────────────────────────────────────────
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "msg_all" ON messages;
DROP POLICY IF EXISTS "messages_participant_select" ON messages;
DROP POLICY IF EXISTS "messages_participant_insert" ON messages;
DROP POLICY IF EXISTS "messages_participant_update" ON messages;
DROP POLICY IF EXISTS "messages_participant_delete" ON messages;

CREATE POLICY "messages_participant_select" ON messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = messages.conversation_id
        AND c.participants @> to_jsonb((auth.jwt() ->> 'sub'))
    )
  );

CREATE POLICY "messages_participant_insert" ON messages
  FOR INSERT WITH CHECK (
    sender_id = (auth.jwt() ->> 'sub')
    AND EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = messages.conversation_id
        AND c.participants @> to_jsonb((auth.jwt() ->> 'sub'))
    )
  );

CREATE POLICY "messages_participant_update" ON messages
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = messages.conversation_id
        AND c.participants @> to_jsonb((auth.jwt() ->> 'sub'))
    )
  );

CREATE POLICY "messages_participant_delete" ON messages
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM conversations c
      WHERE c.id = messages.conversation_id
        AND c.participants @> to_jsonb((auth.jwt() ->> 'sub'))
    )
  );

-- ── bloquages ────────────────────────────────────────────────────────────
ALTER TABLE bloquages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "bloquages_all" ON bloquages;
DROP POLICY IF EXISTS "bloquages_owner_all" ON bloquages;

CREATE POLICY "bloquages_owner_all" ON bloquages
  FOR ALL
  USING (uid = (auth.jwt() ->> 'sub'))
  WITH CHECK (uid = (auth.jwt() ->> 'sub'));

-- ── message_reactions ────────────────────────────────────────────────────
ALTER TABLE message_reactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "message_reactions_all" ON message_reactions;
DROP POLICY IF EXISTS "message_reactions_select" ON message_reactions;
DROP POLICY IF EXISTS "message_reactions_own_write" ON message_reactions;

CREATE POLICY "message_reactions_select" ON message_reactions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM messages m
      JOIN conversations c ON c.id = m.conversation_id
      WHERE m.id = message_reactions.message_id
        AND c.participants @> to_jsonb((auth.jwt() ->> 'sub'))
    )
  );

CREATE POLICY "message_reactions_own_write" ON message_reactions
  FOR ALL
  USING (uid = (auth.jwt() ->> 'sub'))
  WITH CHECK (uid = (auth.jwt() ->> 'sub'));

-- Vérification
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename IN ('conversations','messages','bloquages','message_reactions')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "conversations_participant_select" ON conversations;
-- DROP POLICY IF EXISTS "conversations_participant_insert" ON conversations;
-- DROP POLICY IF EXISTS "conversations_participant_update" ON conversations;
-- DROP POLICY IF EXISTS "conversations_participant_delete" ON conversations;
-- CREATE POLICY "conv_all" ON conversations USING (true) WITH CHECK (true);
--
-- DROP POLICY IF EXISTS "messages_participant_select" ON messages;
-- DROP POLICY IF EXISTS "messages_participant_insert" ON messages;
-- DROP POLICY IF EXISTS "messages_participant_update" ON messages;
-- DROP POLICY IF EXISTS "messages_participant_delete" ON messages;
-- CREATE POLICY "msg_all" ON messages USING (true) WITH CHECK (true);
--
-- DROP POLICY IF EXISTS "bloquages_owner_all" ON bloquages;
-- CREATE POLICY "bloquages_all" ON bloquages USING (true) WITH CHECK (true);
--
-- DROP POLICY IF EXISTS "message_reactions_select" ON message_reactions;
-- DROP POLICY IF EXISTS "message_reactions_own_write" ON message_reactions;
-- CREATE POLICY "message_reactions_all" ON message_reactions USING (true) WITH CHECK (true);
