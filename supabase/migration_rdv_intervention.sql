-- RDV « Intervention » (vétérinaire) — lot 1 (03/11/2026).
--
-- Détartrage, stérilisation, castration, chirurgie, extraction dentaire…
-- sous anesthésie : l'animal est déposé le matin et récupéré plus tard.
--   • rdv.intervention_type : sous-type (null = RDV ordinaire) ;
--     date_heure = heure de dépôt (créneau court), heure_recuperation =
--     récupération prévue, bloc_debut / bloc_fin = temps d'intervention ;
--   • rdv.chirurgie_id : l'intervention (table chirurgies : CR pré-op,
--     opératoire, consignes) ;
--   • rdv.consignes_preop : consignes au propriétaire (à jeun…), copiées
--     du texte par défaut du sous-type, envoyées à la prise du RDV et
--     rappelées la veille ;
--   • rdv.admis_le / sortie_le : animal déposé / récupéré ;
--   • rdv.suivi_hospitalisation : notes de réveil / surveillance ;
--   • consignes_preop_veto : textes par défaut par sous-type, par profil.
-- Agenda de la famille : titre « Intervention … », récupération prévue et
-- consignes dans les notes. Pas de réservation en ligne (créé par le pro).
-- Idempotent.

BEGIN;

ALTER TABLE public.rdv
  ADD COLUMN IF NOT EXISTS intervention_type TEXT,
  ADD COLUMN IF NOT EXISTS heure_recuperation TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS bloc_debut TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS bloc_fin TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS chirurgie_id TEXT,
  ADD COLUMN IF NOT EXISTS consignes_preop TEXT,
  ADD COLUMN IF NOT EXISTS admis_le TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS sortie_le TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS suivi_hospitalisation TEXT;

CREATE INDEX IF NOT EXISTS rdv_intervention_idx ON public.rdv (pro_profile_id, date_heure) WHERE intervention_type IS NOT NULL;

-- Consignes par défaut, par profil vétérinaire et sous-type ({"detartrage": "…"}).
CREATE TABLE IF NOT EXISTS public.consignes_preop_veto (
  pro_profile_id UUID PRIMARY KEY,
  consignes JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.consignes_preop_veto ENABLE ROW LEVEL SECURITY;
-- Lecture : textes non confidentiels (l'équipe de la clinique s'en sert à la prise de RDV).
DROP POLICY IF EXISTS consignes_preop_veto_lecture ON public.consignes_preop_veto;
CREATE POLICY consignes_preop_veto_lecture ON public.consignes_preop_veto FOR SELECT TO anon, authenticated USING (true);
-- Écriture : le titulaire du profil.
DROP POLICY IF EXISTS consignes_preop_veto_ecriture ON public.consignes_preop_veto;
CREATE POLICY consignes_preop_veto_ecriture ON public.consignes_preop_veto FOR ALL TO anon, authenticated
  USING (EXISTS (SELECT 1 FROM user_profiles up WHERE up.id = pro_profile_id AND up.uid::text = auth.jwt() ->> 'sub'))
  WITH CHECK (EXISTS (SELECT 1 FROM user_profiles up WHERE up.id = pro_profile_id AND up.uid::text = auth.jwt() ->> 'sub'));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.consignes_preop_veto TO anon, authenticated;

-- Agenda de la famille : intervention lisible (dépôt, récupération, consignes).
CREATE OR REPLACE FUNCTION public.sync_rdv_agenda()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  pro_name TEXT;
  v_titre TEXT;
  v_notes TEXT;
BEGIN
  SELECT COALESCE(NULLIF(name_elevage,''), NULLIF(profession_pro,''), 'Professionnel')
  INTO pro_name FROM users WHERE uid = NEW.pro_uid LIMIT 1;
  v_titre := 'RDV avec ' || COALESCE(pro_name,'Professionnel');
  v_notes := NEW.motif;
  IF NEW.intervention_type IS NOT NULL THEN
    v_titre := 'Intervention — ' || COALESCE(NULLIF(NEW.motif, ''), 'intervention') || ' (dépôt)';
    v_notes := concat_ws(E'\n',
      COALESCE(pro_name, 'Professionnel'),
      CASE WHEN NEW.heure_recuperation IS NOT NULL
        THEN 'Récupération prévue vers ' || to_char(NEW.heure_recuperation AT TIME ZONE 'Europe/Paris', 'HH24"h"MI') END,
      CASE WHEN NULLIF(trim(COALESCE(NEW.consignes_preop, '')), '') IS NOT NULL
        THEN 'Consignes : ' || NEW.consignes_preop END);
  END IF;
  IF NEW.statut = 'confirme' AND (OLD.statut IS DISTINCT FROM 'confirme'
      OR NEW.date_heure IS DISTINCT FROM OLD.date_heure
      OR NEW.heure_recuperation IS DISTINCT FROM OLD.heure_recuperation
      OR NEW.consignes_preop IS DISTINCT FROM OLD.consignes_preop
      OR NEW.motif IS DISTINCT FROM OLD.motif) THEN
    INSERT INTO agenda_events (uid, titre, type, date_debut, animal_id, notes, rdv_id)
    VALUES (NEW.client_uid, v_titre, 'rdv', NEW.date_heure, NEW.animal_id, v_notes, NEW.id)
    ON CONFLICT (rdv_id) WHERE rdv_id IS NOT NULL
    DO UPDATE SET titre=EXCLUDED.titre, date_debut=EXCLUDED.date_debut, animal_id=EXCLUDED.animal_id, notes=EXCLUDED.notes;
  ELSIF (NEW.statut='annule' OR NEW.statut='refuse') AND OLD.statut='confirme' THEN
    DELETE FROM agenda_events WHERE rdv_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$function$;

-- Aussi au changement d'heure / de récupération / de consignes d'un RDV confirmé.
DROP TRIGGER IF EXISTS rdv_agenda_sync ON public.rdv;
CREATE TRIGGER rdv_agenda_sync AFTER UPDATE OF statut, date_heure, heure_recuperation, consignes_preop, motif ON public.rdv
  FOR EACH ROW EXECUTE FUNCTION public.sync_rdv_agenda();

COMMIT;
