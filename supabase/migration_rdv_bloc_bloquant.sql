-- Temps d'intervention (bloc) bloquant (04/11/2026).
-- Aucun RDV (créé par la clinique, l'ASV ou réservé en ligne) ne peut
-- tomber sur le temps d'intervention d'un vétérinaire :
--   • salle de bloc réservée pour une intervention (occupations_salle avec
--     rdv_id) au nom de ce praticien ;
--   • ou indisponibilité « bloc » (agenda_events couleur 'bloc:<rdv>').
-- Praticien = rdv.instructeur_profile_id (NULL = titulaire). Ne concerne
-- pas les RDV d'intervention eux-mêmes (créneau de dépôt), ni la propre
-- intervention du RDV.
-- Corrige aussi sync_rdv_agenda : un RDV confirmé d'un client SANS compte
-- (client_uid NULL) ne pouvait plus être déplacé (ni sa récupération /
-- ses consignes modifiées) depuis migration_rdv_intervention.sql — l'agenda
-- de la famille n'est écrit que si le client a un compte. Idempotent.

BEGIN;

CREATE OR REPLACE FUNCTION public.pm_rdv_bloc_controle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_debut timestamptz := NEW.date_heure;
  v_fin   timestamptz := NEW.date_heure + make_interval(mins => coalesce(NEW.duree_minutes, 30));
  v_motif text;
BEGIN
  IF NEW.statut NOT IN ('confirme', 'demande') OR NEW.pro_profile_id IS NULL OR NEW.date_heure IS NULL
     OR NEW.intervention_type IS NOT NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND NEW.date_heure IS NOT DISTINCT FROM OLD.date_heure
     AND NEW.duree_minutes IS NOT DISTINCT FROM OLD.duree_minutes
     AND NEW.instructeur_profile_id IS NOT DISTINCT FROM OLD.instructeur_profile_id
     AND OLD.statut IN ('confirme', 'demande') THEN
    RETURN NEW;
  END IF;

  SELECT o.motif INTO v_motif
    FROM occupations_salle o
   WHERE o.clinique_profile_id::text = NEW.pro_profile_id
     AND o.rdv_id IS NOT NULL AND o.rdv_id <> NEW.id
     AND o.praticien_profile_id IS NOT DISTINCT FROM NEW.instructeur_profile_id
     AND o.debut < v_fin
     AND least(o.fin, coalesce(o.liberee_at, o.fin)) > v_debut
   LIMIT 1;
  IF NOT FOUND THEN
    SELECT e.titre INTO v_motif
      FROM agenda_events e
     WHERE e.couleur LIKE 'bloc:%' AND e.couleur <> 'bloc:' || NEW.id::text
       AND coalesce(nullif(e.pro_profile_id, ''), e.profile_id::text) = NEW.pro_profile_id
       AND e.praticien_profile_id IS NOT DISTINCT FROM NEW.instructeur_profile_id
       AND e.date_debut < v_fin
       AND coalesce(e.date_fin, e.date_debut + make_interval(mins => coalesce(e.duree_minutes, 60))) > v_debut
     LIMIT 1;
    IF NOT FOUND THEN RETURN NEW; END IF;
  END IF;
  RAISE EXCEPTION 'Ce créneau est pris par une intervention (bloc) du vétérinaire%. Choisissez un autre horaire ou un autre vétérinaire.',
    CASE WHEN v_motif IS NOT NULL THEN ' : ' || v_motif ELSE '' END
    USING ERRCODE = 'P0001';
END;
$function$;

DROP TRIGGER IF EXISTS trg_rdv_bloc_controle ON public.rdv;
CREATE TRIGGER trg_rdv_bloc_controle
  BEFORE INSERT OR UPDATE OF date_heure, duree_minutes, instructeur_profile_id, statut ON public.rdv
  FOR EACH ROW EXECUTE FUNCTION public.pm_rdv_bloc_controle();

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
  v_animal TEXT;
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
        THEN 'Récupération prévue ' || CASE
          WHEN (NEW.heure_recuperation AT TIME ZONE 'Europe/Paris')::date <> (NEW.date_heure AT TIME ZONE 'Europe/Paris')::date
          THEN 'le ' || to_char(NEW.heure_recuperation AT TIME ZONE 'Europe/Paris', 'DD/MM') || ' ' ELSE '' END
          || 'vers ' || to_char(NEW.heure_recuperation AT TIME ZONE 'Europe/Paris', 'HH24"h"MI') END,
      CASE WHEN NULLIF(trim(COALESCE(NEW.consignes_preop, '')), '') IS NOT NULL
        THEN 'Consignes : ' || NEW.consignes_preop END);
  END IF;
  IF NEW.statut = 'confirme' AND (OLD.statut IS DISTINCT FROM 'confirme'
      OR NEW.date_heure IS DISTINCT FROM OLD.date_heure
      OR NEW.heure_recuperation IS DISTINCT FROM OLD.heure_recuperation
      OR NEW.consignes_preop IS DISTINCT FROM OLD.consignes_preop
      OR NEW.motif IS DISTINCT FROM OLD.motif) THEN
    -- Client sans compte (client_uid NULL) : pas d'agenda à écrire (sinon
    -- toute modification d'un RDV confirmé échouait sur agenda_events.uid).
    -- pro_profile_id = profil du client : l'agenda de l'appli est cloisonné par profil.
    IF NEW.client_uid IS NOT NULL THEN
      INSERT INTO agenda_events (uid, titre, type, date_debut, animal_id, notes, rdv_id, pro_profile_id)
      VALUES (NEW.client_uid, v_titre, 'rdv', NEW.date_heure, NEW.animal_id, v_notes, NEW.id, NEW.client_profile_id)
      ON CONFLICT (rdv_id) WHERE rdv_id IS NOT NULL
      DO UPDATE SET titre=EXCLUDED.titre, date_debut=EXCLUDED.date_debut, animal_id=EXCLUDED.animal_id, notes=EXCLUDED.notes;
    END IF;
    -- Intervention : récupération de l'animal (2e événement).
    IF NEW.client_uid IS NOT NULL THEN
      DELETE FROM agenda_events WHERE couleur = 'recup:' || NEW.id::text;
      IF NEW.intervention_type IS NOT NULL AND NEW.heure_recuperation IS NOT NULL THEN
        SELECT nom INTO v_animal FROM animaux WHERE id::text = NEW.animal_id::text;
        INSERT INTO agenda_events (uid, titre, type, date_debut, duree_minutes, animal_id, notes, couleur, pro_profile_id)
        VALUES (NEW.client_uid,
          'Récupérer ' || COALESCE(NULLIF(v_animal, ''), NULLIF(NEW.animal_nom_manuel, ''), 'votre animal') || ' — ' || COALESCE(pro_name, 'Professionnel'),
          'rdv', NEW.heure_recuperation, 15, NEW.animal_id,
          COALESCE(NULLIF(NEW.motif, ''), 'Intervention') || E'\nHeure prévue : la clinique vous prévient quand votre animal est prêt.',
          'recup:' || NEW.id::text, NEW.client_profile_id);
      END IF;
    END IF;
  ELSIF (NEW.statut='annule' OR NEW.statut='refuse') AND OLD.statut='confirme' THEN
    DELETE FROM agenda_events WHERE rdv_id = NEW.id OR couleur IN ('recup:' || NEW.id::text, 'bloc:' || NEW.id::text);
    -- Intervention annulée : salle de bloc et temps du praticien libérés.
    DELETE FROM occupations_salle WHERE rdv_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$function$;

COMMIT;
