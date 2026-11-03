-- RDV « Intervention » — cohérence des horaires (03/11/2026).
-- Contrôlé en base (en plus des formulaires du site et de l'appli) :
--   • récupération prévue après le dépôt (date_heure) — peut être un autre
--     jour (hospitalisation de plusieurs jours) ;
--   • bloc : fin après le début, début au plus tôt au dépôt, récupération
--     après la fin du bloc ;
--   • étapes de la journée dans l'ordre : réveil / prêt / sortie après
--     l'admission (et pas sans admission).
-- Agenda de la famille : récupération un autre jour que le dépôt → date
-- indiquée (« Récupération prévue le 05/11 vers 17h00 »).
-- Données existantes vérifiées conformes avant ajout. Idempotent.

BEGIN;

ALTER TABLE public.rdv DROP CONSTRAINT IF EXISTS rdv_intervention_horaires_chk;
ALTER TABLE public.rdv ADD CONSTRAINT rdv_intervention_horaires_chk CHECK (
  intervention_type IS NULL OR (
    (heure_recuperation IS NULL OR heure_recuperation > date_heure)
    AND (bloc_debut IS NULL OR bloc_fin IS NULL OR bloc_fin > bloc_debut)
    AND (bloc_debut IS NULL OR bloc_debut >= date_heure)
    AND (heure_recuperation IS NULL OR bloc_fin IS NULL OR heure_recuperation >= bloc_fin)
  )
);

ALTER TABLE public.rdv DROP CONSTRAINT IF EXISTS rdv_intervention_etapes_chk;
ALTER TABLE public.rdv ADD CONSTRAINT rdv_intervention_etapes_chk CHECK (
  intervention_type IS NULL OR (
    (reveil_le IS NULL OR (admis_le IS NOT NULL AND reveil_le >= admis_le))
    AND (pret_le IS NULL OR (admis_le IS NOT NULL AND pret_le >= admis_le))
    AND (sortie_le IS NULL OR (admis_le IS NOT NULL AND sortie_le >= admis_le))
  )
);

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
    DELETE FROM agenda_events WHERE rdv_id = NEW.id OR couleur IN ('recup:' || NEW.id::text, 'bloc:' || NEW.id::text);
    -- Intervention annulée : salle de bloc et temps du praticien libérés.
    DELETE FROM occupations_salle WHERE rdv_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$function$;

COMMIT;
