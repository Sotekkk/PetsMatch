-- RDV « Intervention » : animal récupéré avant la fin du créneau de bloc (04/11/2026).
-- Le temps restant redevient libre pour d'autres RDV :
--   • salle de bloc : occupations_salle.liberee_at = heure de sortie (déjà
--     respecté par pm_rdv_bloc_controle, pm_plages_occupees et les plannings) ;
--   • sans salle : indisponibilité 'bloc:<rdv>' raccourcie, ou retirée si
--     l'animal est reparti avant le début de l'intervention.
-- « Annuler la sortie » remet le créneau prévu (rdv.bloc_debut / bloc_fin) ; une
-- salle libérée à la main à une autre heure n'est pas touchée.
-- Reprend pm_rdv_sortie_statut de migration_rdv_intervention_recupere.sql. Idempotent.

BEGIN;

CREATE OR REPLACE FUNCTION public.pm_rdv_sortie_statut()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_nom TEXT;
  v_animal TEXT;
BEGIN
  IF NEW.intervention_type IS NULL THEN
    RETURN NEW;
  END IF;

  -- Temps de bloc restant libéré à la sortie, remis si la sortie est annulée.
  IF NEW.sortie_le IS NOT NULL AND OLD.sortie_le IS NULL AND NEW.bloc_fin IS NOT NULL AND NEW.sortie_le < NEW.bloc_fin THEN
    UPDATE occupations_salle SET liberee_at = NEW.sortie_le WHERE rdv_id = NEW.id AND liberee_at IS NULL;
    DELETE FROM agenda_events WHERE couleur = 'bloc:' || NEW.id::text AND date_debut >= NEW.sortie_le;
    UPDATE agenda_events SET date_fin = NEW.sortie_le, duree_minutes = NULL WHERE couleur = 'bloc:' || NEW.id::text;
  ELSIF NEW.sortie_le IS NULL AND OLD.sortie_le IS NOT NULL AND NEW.bloc_fin IS NOT NULL AND OLD.sortie_le < NEW.bloc_fin THEN
    UPDATE occupations_salle SET liberee_at = NULL WHERE rdv_id = NEW.id AND liberee_at = OLD.sortie_le;
    IF NOT EXISTS (SELECT 1 FROM occupations_salle WHERE rdv_id = NEW.id) THEN
      UPDATE agenda_events SET date_fin = NEW.bloc_fin, duree_minutes = NULL WHERE couleur = 'bloc:' || NEW.id::text;
      IF NOT FOUND AND NEW.bloc_debut IS NOT NULL THEN
        SELECT nom INTO v_animal FROM animaux WHERE id::text = NEW.animal_id::text;
        INSERT INTO agenda_events (uid, titre, type, date_debut, date_fin, pro_profile_id, praticien_profile_id, couleur)
        VALUES (NEW.pro_uid,
          'Intervention — ' || COALESCE(NULLIF(NEW.motif, ''), 'intervention')
            || COALESCE(' — ' || COALESCE(NULLIF(v_animal, ''), NULLIF(NEW.animal_nom_manuel, '')), ''),
          'indisponible', NEW.bloc_debut, NEW.bloc_fin, NEW.pro_profile_id, NEW.instructeur_profile_id, 'bloc:' || NEW.id::text);
      END IF;
    END IF;
  END IF;

  IF NEW.sortie_le IS NOT NULL AND OLD.sortie_le IS NULL AND NEW.statut = 'confirme' THEN
    NEW.statut := 'termine';
    NEW.termine_at := NEW.sortie_le;
    -- Demande d'avis, une seule fois (mêmes règles que le bouton « Terminé »).
    IF NEW.client_uid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM avis_pro a WHERE a.pro_uid = NEW.pro_uid AND a.client_uid = NEW.client_uid
                         AND (NULLIF(NEW.pro_profile_id::text, '') IS NULL OR a.pro_profile_id::text = NEW.pro_profile_id::text))
       AND NOT EXISTS (SELECT 1 FROM notifications n WHERE n.uid = NEW.client_uid AND n.type = 'avis_demande'
                         AND n.data @> jsonb_build_object('rdv_id', NEW.id)) THEN
      SELECT NULLIF(trim(COALESCE(nom, '')), '') INTO v_nom
        FROM user_profiles_complet WHERE id::text = NEW.pro_profile_id::text LIMIT 1;
      v_nom := COALESCE(v_nom, 'votre professionnel');
      INSERT INTO notifications (uid, type, title, body, profile_id, data, read)
      VALUES (NEW.client_uid, 'avis_demande', 'Votre avis compte',
        'Comment s''est passée votre séance avec ' || v_nom || ' ? Laissez un avis.',
        NULLIF(NEW.client_profile_id::text, ''),
        jsonb_strip_nulls(jsonb_build_object('rdv_id', NEW.id, 'pro_uid', NEW.pro_uid, 'pro_profile_id', NULLIF(NEW.pro_profile_id::text, ''), 'pro_nom', v_nom,
          'url', '/services/pro/' || NEW.pro_uid || '?avis=1' || COALESCE('&profileId=' || NULLIF(NEW.pro_profile_id::text, ''), ''))),
        false);
    END IF;
  ELSIF NEW.sortie_le IS NULL AND OLD.sortie_le IS NOT NULL AND NEW.statut = 'termine'
        AND OLD.termine_at IS NOT DISTINCT FROM OLD.sortie_le THEN
    NEW.statut := 'confirme';
    NEW.termine_at := NULL;
  END IF;
  RETURN NEW;
END;
$function$;

-- Sorties déjà notées avant la fin du bloc.
UPDATE occupations_salle o SET liberee_at = r.sortie_le
  FROM rdv r
 WHERE o.rdv_id = r.id AND o.liberee_at IS NULL
   AND r.intervention_type IS NOT NULL AND r.sortie_le IS NOT NULL AND r.bloc_fin IS NOT NULL AND r.sortie_le < r.bloc_fin;
DELETE FROM agenda_events e USING rdv r
 WHERE e.couleur = 'bloc:' || r.id::text AND e.date_debut >= r.sortie_le
   AND r.intervention_type IS NOT NULL AND r.bloc_fin IS NOT NULL AND r.sortie_le < r.bloc_fin;
UPDATE agenda_events e SET date_fin = r.sortie_le, duree_minutes = NULL
  FROM rdv r
 WHERE e.couleur = 'bloc:' || r.id::text
   AND r.intervention_type IS NOT NULL AND r.bloc_fin IS NOT NULL AND r.sortie_le < r.bloc_fin;

COMMIT;
