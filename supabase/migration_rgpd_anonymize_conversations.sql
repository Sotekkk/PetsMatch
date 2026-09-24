-- ══════════════════════════════════════════════════════════════════════════
-- RGPD — anonymisation des conversations à la suppression de compte
-- ══════════════════════════════════════════════════════════════════════════
-- `conversations.participants_info` est un instantané JSON figé à la
-- création de la conversation ({ "<uid>": { "name": "...", "photo": "..." } })
-- — supprimer la ligne `users`/`user_profiles` ne le met PAS à jour
-- automatiquement (ce n'est pas une jointure live). Sans cette fonction,
-- le nom d'un compte supprimé resterait affiché tel quel indéfiniment dans
-- les conversations où il a participé. Les messages eux-mêmes
-- (`messages.sender_id`, leur texte) restent inchangés — casser leur
-- contenu casserait la conversation pour l'autre participant, seul le NOM
-- affiché change (comme WhatsApp/Signal).
--
-- Appelée uniquement via service_role (api/account/anonymize) au moment de
-- la suppression de compte — jamais côté client.
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.anonymize_conversations_participant(p_uid TEXT)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE conversations
  SET participants_info = (participants_info - p_uid)
        || jsonb_build_object(p_uid, jsonb_build_object('name', 'Compte supprimé'))
  WHERE participants_info ? p_uid;
END;
$$;
