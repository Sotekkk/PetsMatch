-- RDV « Intervention » : récupération de l'animal dans l'agenda de la
-- famille (03/11/2026, après migration_rdv_intervention.sql).
-- Un 2e événement « Récupérer <animal> » à l'heure de récupération prévue
-- (couleur = 'recup:<rdv>'), recréé quand la clinique change l'heure, retiré
-- à l'annulation. Le RDV de dépôt garde son événement (rdv_id). Idempotent.

BEGIN;

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
        THEN 'Récupération prévue vers ' || to_char(NEW.heure_recuperation AT TIME ZONE 'Europe/Paris', 'HH24"h"MI') END,
      CASE WHEN NULLIF(trim(COALESCE(NEW.consignes_preop, '')), '') IS NOT NULL
        THEN 'Consignes : ' || NEW.consignes_preop END);
  END IF;
  IF NEW.statut = 'confirme' AND (OLD.statut IS DISTINCT FROM 'confirme'
      OR NEW.date_heure IS DISTINCT FROM OLD.date_heure
      OR NEW.heure_recuperation IS DISTINCT FROM OLD.heure_recuperation
      OR NEW.consignes_preop IS DISTINCT FROM OLD.consignes_preop
      OR NEW.motif IS DISTINCT FROM OLD.motif) THEN
    -- pro_profile_id = profil du client : l'agenda de l'appli est cloisonné par profil.
    INSERT INTO agenda_events (uid, titre, type, date_debut, animal_id, notes, rdv_id, pro_profile_id)
    VALUES (NEW.client_uid, v_titre, 'rdv', NEW.date_heure, NEW.animal_id, v_notes, NEW.id, NEW.client_profile_id)
    ON CONFLICT (rdv_id) WHERE rdv_id IS NOT NULL
    DO UPDATE SET titre=EXCLUDED.titre, date_debut=EXCLUDED.date_debut, animal_id=EXCLUDED.animal_id, notes=EXCLUDED.notes;
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
    DELETE FROM agenda_events WHERE rdv_id = NEW.id OR couleur = 'recup:' || NEW.id::text;
  END IF;
  RETURN NEW;
END;
$function$;

COMMIT;
