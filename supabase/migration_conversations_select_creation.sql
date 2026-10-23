-- ════════════════════════════════════════════════════════════════════════
-- Messagerie : « new row violates row-level security policy for table
-- conversations » (42501) à la PREMIÈRE prise de contact (ex. « Contacter
-- l'éleveur » sur une annonce, appli + site).
--
-- Cause : la création fait INSERT … RETURNING (select('id')) ; la ligne
-- renvoyée passe la policy de lecture conv_select, qui appelait seulement
-- pm_est_participant(id) — une fonction qui relit la table et ne voit pas
-- encore la ligne en cours d'insertion → refus.
-- Correctif : conv_select teste d'abord les colonnes de la ligne elle-même
-- (participants / participant_ids), même règle que pm_est_participant.
-- Rien d'autre ne change. Idempotent.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

DROP POLICY IF EXISTS conv_select ON public.conversations;
CREATE POLICY conv_select ON public.conversations
  FOR SELECT TO anon, authenticated
  USING (
    (auth.jwt() ->> 'sub') IS NOT NULL AND (
      participants ? (auth.jwt() ->> 'sub')
      OR (auth.jwt() ->> 'sub') = ANY (regexp_split_to_array(coalesce(participant_ids, ''), '[,_]'))
    )
    OR public.pm_est_participant(id)
    OR public.is_admin_uid(auth.jwt() ->> 'sub')
  );

COMMIT;
