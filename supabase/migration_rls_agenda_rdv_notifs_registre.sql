-- ════════════════════════════════════════════════════════════════════════
-- RLS : agenda_events, rdv, notifications, registre_mouvements.
--
-- Avant : des policies « USING (true) » (ae_*, rdv_allow_all, "Allow all",
-- "service role insert", reg_mvt_allow_all) annulaient les policies
-- propriétaire / cogérant → n'importe qui, sans compte, lisait, créait,
-- modifiait et supprimait RDV, agendas, notifications et registres
-- d'entrée-sortie de tous les comptes.
-- Et les policies « related » existantes ignoraient les EMPLOYÉS (qui
-- passaient par les policies ouvertes) et ne scopaient pas le cogérant
-- par profil.
--
-- Fonction commune pm_acces_compte(uid du compte, profil, droits) :
--   • le titulaire du compte ;
--   • cogérant actif, limité au profil de sa cogérance ;
--   • employé actif, limité au profil de son emploi ; si des droits sont
--     demandés, il doit en avoir un (employe_permissions).
-- (même logique que can_access_registre_sanitaire, 30/09)
--
-- Après :
--   • agenda_events : le compte (titulaire / cogérant / employé) ; le client
--     d'un RDV peut supprimer l'événement du pro lié à ce RDV (annulation
--     depuis le site) ;
--   • rdv : le client, ou le compte du pro ;
--   • notifications : lire / modifier / supprimer les siennes (+ cogérant,
--     inchangé) ; en créer pour quelqu'un = être connecté ;
--   • registre_mouvements : lire = le compte, ou un propriétaire (actuel
--     ou passé) de l'animal ; écrire = le compte avec un droit d'écriture
--     animaux, ou l'une des deux parties d'une CESSION (la partie qui
--     finalise écrit la sortie du cédant ET l'entrée de l'acquéreur).
-- Serveur (Cloud Functions, Edge Functions, crons) : service_role, non
-- affecté.
--
-- ⚠ Le site en ligne au 30/09 n'envoie pas le jeton Firebase.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

-- Profil passé en TEXTE (colonnes text ou uuid selon les tables ;
-- chaîne vide = pas de profil).
CREATE OR REPLACE FUNCTION public.pm_acces_compte(
  p_uid_compte text,
  p_profile_id text,
  p_droits text[] DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (auth.jwt() ->> 'sub') IS NOT NULL AND p_uid_compte IS NOT NULL AND (
    p_uid_compte = (auth.jwt() ->> 'sub')
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = p_uid_compte AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
        AND (nullif(p_profile_id, '') IS NULL OR c.elevage_profile_id IS NULL
             OR c.elevage_profile_id::text = p_profile_id)
    )
    OR EXISTS (
      SELECT 1 FROM employes e
      WHERE e.uid_eleveur = p_uid_compte AND e.uid_employe = (auth.jwt() ->> 'sub')
        AND e.actif = true
        AND (nullif(p_profile_id, '') IS NULL OR e.eleveur_profile_id IS NULL
             OR e.eleveur_profile_id::text = p_profile_id)
        AND (
          p_droits IS NULL
          OR EXISTS (
            SELECT 1 FROM employe_permissions ep
            WHERE ep.eleveur_profile_id = e.eleveur_profile_id
              AND ep.employe_profile_id = e.employe_profile_id
              AND ep.permission = ANY (p_droits)
          )
        )
    )
  );
$$;
GRANT EXECUTE ON FUNCTION public.pm_acces_compte(text, text, text[]) TO anon, authenticated;

-- Partie d'une cession de cet animal (cédant ou acquéreur), et la ligne
-- écrite concerne bien l'une des deux parties.
CREATE OR REPLACE FUNCTION public.pm_partie_cession(p_animal_id text, p_uid_ligne text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (auth.jwt() ->> 'sub') IS NOT NULL AND (
    EXISTS (
      SELECT 1 FROM cessions c
      WHERE c.animal_id = p_animal_id
        AND (auth.jwt() ->> 'sub') IN (c.uid_eleveur, c.uid_acquereur)
        AND p_uid_ligne IN (c.uid_eleveur, c.uid_acquereur)
    )
    OR (
      EXISTS (SELECT 1 FROM animaux_proprietes ap
              WHERE ap.animal_id = p_animal_id AND ap.uid_proprio = (auth.jwt() ->> 'sub'))
      AND EXISTS (SELECT 1 FROM animaux_proprietes ap
                  WHERE ap.animal_id = p_animal_id AND ap.uid_proprio = p_uid_ligne)
    )
  );
$$;
GRANT EXECUTE ON FUNCTION public.pm_partie_cession(text, text) TO anon, authenticated;

-- ── agenda_events ──────────────────────────────────────────────────────
DROP POLICY IF EXISTS ae_select ON public.agenda_events;
DROP POLICY IF EXISTS ae_insert ON public.agenda_events;
DROP POLICY IF EXISTS ae_update ON public.agenda_events;
DROP POLICY IF EXISTS ae_delete ON public.agenda_events;
DROP POLICY IF EXISTS agenda_events_related_select ON public.agenda_events;
DROP POLICY IF EXISTS agenda_events_related_insert ON public.agenda_events;
DROP POLICY IF EXISTS agenda_events_related_update ON public.agenda_events;
DROP POLICY IF EXISTS agenda_events_related_delete ON public.agenda_events;

-- Le client d'un RDV voit (et peut supprimer, cf. delete) l'événement du pro
-- lié à ce RDV : une suppression exige aussi la visibilité de la ligne.
CREATE POLICY agenda_events_related_select ON public.agenda_events
  FOR SELECT TO anon, authenticated
  USING (
    public.pm_acces_compte(uid, coalesce(nullif(pro_profile_id, ''), profile_id::text))
    OR EXISTS (
      SELECT 1 FROM public.rdv r
      WHERE r.client_uid = (auth.jwt() ->> 'sub')
        AND (r.id = agenda_events.rdv_id OR agenda_events.couleur = 'rdv:' || r.id::text)
    )
  );
CREATE POLICY agenda_events_related_insert ON public.agenda_events
  FOR INSERT TO anon, authenticated
  WITH CHECK (public.pm_acces_compte(uid, coalesce(nullif(pro_profile_id, ''), profile_id::text)));
CREATE POLICY agenda_events_related_update ON public.agenda_events
  FOR UPDATE TO anon, authenticated
  USING (public.pm_acces_compte(uid, coalesce(nullif(pro_profile_id, ''), profile_id::text)))
  WITH CHECK (public.pm_acces_compte(uid, coalesce(nullif(pro_profile_id, ''), profile_id::text)));
CREATE POLICY agenda_events_related_delete ON public.agenda_events
  FOR DELETE TO anon, authenticated
  USING (
    public.pm_acces_compte(uid, coalesce(nullif(pro_profile_id, ''), profile_id::text))
    OR EXISTS (
      SELECT 1 FROM public.rdv r
      WHERE r.client_uid = (auth.jwt() ->> 'sub')
        AND (r.id = agenda_events.rdv_id OR agenda_events.couleur = 'rdv:' || r.id::text)
    )
  );

-- ── rdv ────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS rdv_allow_all ON public.rdv;
DROP POLICY IF EXISTS rdv_related_select ON public.rdv;
DROP POLICY IF EXISTS rdv_related_insert ON public.rdv;
DROP POLICY IF EXISTS rdv_related_update ON public.rdv;
DROP POLICY IF EXISTS rdv_related_delete ON public.rdv;

CREATE POLICY rdv_related_select ON public.rdv
  FOR SELECT TO anon, authenticated
  USING ((auth.jwt() ->> 'sub') = client_uid OR public.pm_acces_compte(pro_uid, pro_profile_id));
CREATE POLICY rdv_related_insert ON public.rdv
  FOR INSERT TO anon, authenticated
  WITH CHECK ((auth.jwt() ->> 'sub') = client_uid OR public.pm_acces_compte(pro_uid, pro_profile_id));
CREATE POLICY rdv_related_update ON public.rdv
  FOR UPDATE TO anon, authenticated
  USING ((auth.jwt() ->> 'sub') = client_uid OR public.pm_acces_compte(pro_uid, pro_profile_id))
  WITH CHECK ((auth.jwt() ->> 'sub') = client_uid OR public.pm_acces_compte(pro_uid, pro_profile_id));
CREATE POLICY rdv_related_delete ON public.rdv
  FOR DELETE TO anon, authenticated
  USING ((auth.jwt() ->> 'sub') = client_uid OR public.pm_acces_compte(pro_uid, pro_profile_id));

-- ── notifications ──────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Allow all" ON public.notifications;
DROP POLICY IF EXISTS "service role insert" ON public.notifications;
DROP POLICY IF EXISTS allow_insert_notifications ON public.notifications;
-- auth.uid() convertit le sub en uuid : un uid Firebase n'en est pas un →
-- erreur 22P02 dès que la policy est évaluée (masquée jusqu'ici par
-- "Allow all"). Doublon de notifications_owner_or_cogerant_select.
DROP POLICY IF EXISTS "users read own notifs" ON public.notifications;
CREATE POLICY allow_insert_notifications ON public.notifications
  FOR INSERT TO anon, authenticated
  WITH CHECK ((auth.jwt() ->> 'sub') IS NOT NULL AND uid IS NOT NULL AND uid <> '');
-- notifications_owner_or_cogerant_select / _update / _delete conservées.

-- ── registre_mouvements ────────────────────────────────────────────────
DROP POLICY IF EXISTS reg_mvt_allow_all ON public.registre_mouvements;
DROP POLICY IF EXISTS reg_mvt_select ON public.registre_mouvements;
DROP POLICY IF EXISTS reg_mvt_insert ON public.registre_mouvements;
DROP POLICY IF EXISTS reg_mvt_update ON public.registre_mouvements;
DROP POLICY IF EXISTS reg_mvt_delete ON public.registre_mouvements;

CREATE POLICY reg_mvt_select ON public.registre_mouvements
  FOR SELECT TO anon, authenticated
  USING (
    public.pm_acces_compte(uid_eleveur, eleveur_profile_id::text)
    OR EXISTS (SELECT 1 FROM public.animaux_proprietes ap
               WHERE ap.animal_id = registre_mouvements.animal_id
                 AND ap.uid_proprio = (auth.jwt() ->> 'sub'))
  );
CREATE POLICY reg_mvt_insert ON public.registre_mouvements
  FOR INSERT TO anon, authenticated
  WITH CHECK (
    public.pm_acces_compte(uid_eleveur, eleveur_profile_id::text,
                           ARRAY['write_animaux', 'write_sante', 'write_repro'])
    OR (motif = 'cession' AND public.pm_partie_cession(animal_id, uid_eleveur))
  );
CREATE POLICY reg_mvt_update ON public.registre_mouvements
  FOR UPDATE TO anon, authenticated
  USING (public.pm_acces_compte(uid_eleveur, eleveur_profile_id::text,
                                ARRAY['write_animaux', 'write_sante', 'write_repro']))
  WITH CHECK (public.pm_acces_compte(uid_eleveur, eleveur_profile_id::text,
                                     ARRAY['write_animaux', 'write_sante', 'write_repro']));
CREATE POLICY reg_mvt_delete ON public.registre_mouvements
  FOR DELETE TO anon, authenticated
  USING (public.pm_acces_compte(uid_eleveur, eleveur_profile_id::text,
                                ARRAY['write_animaux', 'write_sante', 'write_repro']));

COMMIT;
