-- ════════════════════════════════════════════════════════════════════════
-- RLS agenda_events : le pro d'un RDV écrit l'événement du CLIENT lié à ce RDV.
--
-- Bug (08/10/2026) : accepter un RDV → « new row violates row-level security
-- policy for table agenda_events ». À la confirmation, l'appli et le site
-- posent l'événement dans l'agenda du client (uid = client, rdv_id = RDV) ;
-- depuis migration_rls_agenda_rdv_notifs_registre.sql, seul le compte
-- lui-même peut écrire dans son agenda → refusé pour le pro (tous métiers),
-- y compris l'employé de clinique qui valide pour la clinique.
--
-- Ajout (sans rien retirer) : le compte du PRO d'un RDV (titulaire, cogérant,
-- employé — pm_acces_compte) peut lire / créer / modifier / supprimer
-- l'événement lié à CE RDV, et uniquement pour le client de ce RDV.
-- Idempotent. Staging d'abord (feedback RLS : tests par rôle).
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

-- (rdv_id comparé en texte : type de agenda_events.rdv_id non garanti.)
-- Le pro du RDV `p_rdv_id` (dont l'événement est destiné à `p_uid`, le client).
CREATE OR REPLACE FUNCTION public.pm_pro_du_rdv(p_rdv_id text, p_uid text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_rdv_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM rdv r
     WHERE r.id::text = p_rdv_id
       AND r.client_uid = p_uid
       AND public.pm_acces_compte(r.pro_uid, r.pro_profile_id)
  );
$$;
GRANT EXECUTE ON FUNCTION public.pm_pro_du_rdv(text, text) TO anon, authenticated;

DROP POLICY IF EXISTS agenda_events_rdv_pro_select ON public.agenda_events;
DROP POLICY IF EXISTS agenda_events_rdv_pro_insert ON public.agenda_events;
DROP POLICY IF EXISTS agenda_events_rdv_pro_update ON public.agenda_events;
DROP POLICY IF EXISTS agenda_events_rdv_pro_delete ON public.agenda_events;

CREATE POLICY agenda_events_rdv_pro_select ON public.agenda_events
  FOR SELECT TO anon, authenticated
  USING (public.pm_pro_du_rdv(rdv_id::text, uid));
CREATE POLICY agenda_events_rdv_pro_insert ON public.agenda_events
  FOR INSERT TO anon, authenticated
  WITH CHECK (public.pm_pro_du_rdv(rdv_id::text, uid));
CREATE POLICY agenda_events_rdv_pro_update ON public.agenda_events
  FOR UPDATE TO anon, authenticated
  USING (public.pm_pro_du_rdv(rdv_id::text, uid))
  WITH CHECK (public.pm_pro_du_rdv(rdv_id::text, uid));
CREATE POLICY agenda_events_rdv_pro_delete ON public.agenda_events
  FOR DELETE TO anon, authenticated
  USING (public.pm_pro_du_rdv(rdv_id::text, uid));

COMMIT;
