-- ════════════════════════════════════════════════════════════════════════
-- RLS messagerie : conversations, messages, message_reactions.
--
-- Avant : une seule policy « ALL USING (true) » par table (contournement
-- d'avant l'envoi du jeton Firebase, 22/09) → n'importe qui, SANS compte,
-- pouvait lire les 561 messages privés (texte, images, positions GPS) et
-- les 30 conversations, en écrire ou en effacer.
--
-- Après : seuls les PARTICIPANTS d'une conversation (liste `participants`,
-- repli sur `participant_ids`) y ont accès.
--   (`participant_ids` : séparateur « , » ou « _ » selon l'écran de création)
--   • conversations : lire / modifier / supprimer si participant ; créer
--     une conversation dont on fait partie. Quitter un groupe = se retirer
--     soi-même de `participants` (petfriend_chat_page) → autorisé pour les
--     groupes ;
--   • messages : lire / supprimer si participant ; écrire en son propre nom
--     (sender_id = soi) dans une conversation dont on fait partie ;
--   • message_reactions : lire celles des messages visibles ; ajouter /
--     retirer SES réactions ;
--   • admins (users.is_admin) : lecture, pour la modération des
--     conversations signalées (page /admin).
-- Non affectés : trigger notify_new_message (SECURITY DEFINER), Cloud
-- Functions / Edge Functions (service_role).
--
-- ⚠ Le site en ligne au 30/09 n'envoie pas le jeton Firebase : sa
--   messagerie ne marchera qu'une fois redéployé.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

-- Participant d'une conversation (SECURITY DEFINER : évite que la policy de
-- messages dépende de celle de conversations).
CREATE OR REPLACE FUNCTION public.pm_est_participant(p_conversation_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT (auth.jwt() ->> 'sub') IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.conversations c
    WHERE c.id = p_conversation_id
      AND (c.participants ? (auth.jwt() ->> 'sub')
           OR (auth.jwt() ->> 'sub') = ANY (regexp_split_to_array(coalesce(c.participant_ids, ''), '[,_]')))
  );
$$;

-- Message visible (pour les réactions).
CREATE OR REPLACE FUNCTION public.pm_message_visible(p_message_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.messages m
    WHERE m.id = p_message_id AND public.pm_est_participant(m.conversation_id)
  );
$$;

GRANT EXECUTE ON FUNCTION public.pm_est_participant(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pm_message_visible(text) TO anon, authenticated;

-- ── conversations ──────────────────────────────────────────────────────
DROP POLICY IF EXISTS conv_all ON public.conversations;
DROP POLICY IF EXISTS conv_select ON public.conversations;
DROP POLICY IF EXISTS conv_insert ON public.conversations;
DROP POLICY IF EXISTS conv_update ON public.conversations;
DROP POLICY IF EXISTS conv_delete ON public.conversations;

CREATE POLICY conv_select ON public.conversations
  FOR SELECT TO anon, authenticated
  USING (public.pm_est_participant(id) OR public.is_admin_uid(auth.jwt() ->> 'sub'));

CREATE POLICY conv_insert ON public.conversations
  FOR INSERT TO anon, authenticated
  WITH CHECK (auth.jwt() ->> 'sub' IS NOT NULL AND participants ? (auth.jwt() ->> 'sub'));

CREATE POLICY conv_update ON public.conversations
  FOR UPDATE TO anon, authenticated
  USING (public.pm_est_participant(id))
  WITH CHECK (
    auth.jwt() ->> 'sub' IS NOT NULL
    AND (participants ? (auth.jwt() ->> 'sub') OR type = 'groupe')
  );

CREATE POLICY conv_delete ON public.conversations
  FOR DELETE TO anon, authenticated
  USING (public.pm_est_participant(id));

-- ── messages ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS msg_all ON public.messages;
DROP POLICY IF EXISTS msg_select ON public.messages;
DROP POLICY IF EXISTS msg_insert ON public.messages;
DROP POLICY IF EXISTS msg_update ON public.messages;
DROP POLICY IF EXISTS msg_delete ON public.messages;

CREATE POLICY msg_select ON public.messages
  FOR SELECT TO anon, authenticated
  USING (public.pm_est_participant(conversation_id) OR public.is_admin_uid(auth.jwt() ->> 'sub'));

CREATE POLICY msg_insert ON public.messages
  FOR INSERT TO anon, authenticated
  WITH CHECK (sender_id = auth.jwt() ->> 'sub' AND public.pm_est_participant(conversation_id));

CREATE POLICY msg_update ON public.messages
  FOR UPDATE TO anon, authenticated
  USING (public.pm_est_participant(conversation_id))
  WITH CHECK (public.pm_est_participant(conversation_id));

CREATE POLICY msg_delete ON public.messages
  FOR DELETE TO anon, authenticated
  USING (public.pm_est_participant(conversation_id));

-- ── message_reactions ──────────────────────────────────────────────────
DROP POLICY IF EXISTS allow_all_reactions ON public.message_reactions;
DROP POLICY IF EXISTS message_reactions_all ON public.message_reactions;
DROP POLICY IF EXISTS reactions_select ON public.message_reactions;
DROP POLICY IF EXISTS reactions_insert ON public.message_reactions;
DROP POLICY IF EXISTS reactions_update ON public.message_reactions;
DROP POLICY IF EXISTS reactions_delete ON public.message_reactions;

CREATE POLICY reactions_select ON public.message_reactions
  FOR SELECT TO anon, authenticated
  USING (public.pm_message_visible(message_id));

CREATE POLICY reactions_insert ON public.message_reactions
  FOR INSERT TO anon, authenticated
  WITH CHECK (uid = auth.jwt() ->> 'sub' AND public.pm_message_visible(message_id));

CREATE POLICY reactions_update ON public.message_reactions
  FOR UPDATE TO anon, authenticated
  USING (uid = auth.jwt() ->> 'sub')
  WITH CHECK (uid = auth.jwt() ->> 'sub' AND public.pm_message_visible(message_id));

CREATE POLICY reactions_delete ON public.message_reactions
  FOR DELETE TO anon, authenticated
  USING (uid = auth.jwt() ->> 'sub');

COMMIT;
