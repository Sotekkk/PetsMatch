-- RDV « Intervention » : animal récupéré = RDV terminé (04/11/2026).
--   • sortie_le renseigné sur un RDV confirmé → statut 'termine', termine_at =
--     heure de sortie, demande d'avis à la famille (comme le bouton « Terminé »).
--   • « Annuler la sortie » → retour à 'confirme', seulement si c'est la sortie
--     qui avait terminé le RDV (termine_at = sortie_le) : un RDV clôturé avant
--     (« Terminer la consultation ») reste terminé.
--   • Agenda de la famille : l'événement « Récupérer … » devient « Récupération
--     de … effectuée » à l'heure réelle (récupération plus tôt que prévu), et
--     l'événement de dépôt indique l'heure réelle.
-- « Terminer la consultation » ne note PAS la sortie : on peut envoyer les
-- documents alors que l'animal reste hospitalisé.
-- Reprend sync_rdv_agenda de migration_rdv_agenda_nom_profil.sql. Idempotent.

BEGIN;

-- Déjà là en prod (migration_retard_auto.sql) ; absente du staging.
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS termine_at timestamptz;

CREATE OR REPLACE FUNCTION public.pm_rdv_sortie_statut()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_nom TEXT;
BEGIN
  IF NEW.intervention_type IS NULL THEN
    RETURN NEW;
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

DROP TRIGGER IF EXISTS trg_rdv_sortie_statut ON public.rdv;
CREATE TRIGGER trg_rdv_sortie_statut BEFORE UPDATE OF sortie_le ON public.rdv
  FOR EACH ROW EXECUTE FUNCTION public.pm_rdv_sortie_statut();

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
  -- Nom du PROFIL du RDV (clinique, cabinet…), sinon celui du compte.
  SELECT NULLIF(trim(COALESCE(nom, '')), '') INTO pro_name
    FROM user_profiles_complet WHERE id::text = NEW.pro_profile_id LIMIT 1;
  IF pro_name IS NULL THEN
    SELECT COALESCE(NULLIF(name_elevage,''), NULLIF(profession_pro,''), 'Professionnel')
    INTO pro_name FROM users WHERE uid = NEW.pro_uid LIMIT 1;
  END IF;
  v_titre := 'RDV avec ' || COALESCE(pro_name,'Professionnel');
  v_notes := NEW.motif;
  IF NEW.intervention_type IS NOT NULL THEN
    v_titre := 'Intervention — ' || COALESCE(NULLIF(NEW.motif, ''), 'intervention') || ' (dépôt)';
    v_notes := concat_ws(E'\n',
      COALESCE(pro_name, 'Professionnel'),
      CASE WHEN NEW.sortie_le IS NOT NULL
        THEN 'Récupération effectuée le ' || to_char(NEW.sortie_le AT TIME ZONE 'Europe/Paris', 'DD/MM') || ' à ' || to_char(NEW.sortie_le AT TIME ZONE 'Europe/Paris', 'HH24"h"MI')
      WHEN NEW.heure_recuperation IS NOT NULL
        THEN 'Récupération prévue ' || CASE
          WHEN (NEW.heure_recuperation AT TIME ZONE 'Europe/Paris')::date <> (NEW.date_heure AT TIME ZONE 'Europe/Paris')::date
          THEN 'le ' || to_char(NEW.heure_recuperation AT TIME ZONE 'Europe/Paris', 'DD/MM') || ' ' ELSE '' END
          || 'vers ' || to_char(NEW.heure_recuperation AT TIME ZONE 'Europe/Paris', 'HH24"h"MI') END,
      CASE WHEN NULLIF(trim(COALESCE(NEW.consignes_preop, '')), '') IS NOT NULL
        THEN 'Consignes : ' || NEW.consignes_preop END);
  END IF;
  IF (NEW.statut = 'confirme' AND (OLD.statut IS DISTINCT FROM 'confirme'
      OR NEW.date_heure IS DISTINCT FROM OLD.date_heure
      OR NEW.heure_recuperation IS DISTINCT FROM OLD.heure_recuperation
      OR NEW.consignes_preop IS DISTINCT FROM OLD.consignes_preop
      OR NEW.motif IS DISTINCT FROM OLD.motif))
     -- Sortie notée ou annulée : RDV terminé compris.
     OR (NEW.intervention_type IS NOT NULL AND NEW.statut = 'termine' AND NEW.sortie_le IS DISTINCT FROM OLD.sortie_le) THEN
    -- Client sans compte (client_uid NULL) : pas d'agenda à écrire (sinon
    -- toute modification d'un RDV confirmé échouait sur agenda_events.uid).
    -- pro_profile_id = profil du client : l'agenda de l'appli est cloisonné par profil.
    IF NEW.client_uid IS NOT NULL THEN
      INSERT INTO agenda_events (uid, titre, type, date_debut, animal_id, notes, rdv_id, pro_profile_id)
      VALUES (NEW.client_uid, v_titre, 'rdv', NEW.date_heure, NEW.animal_id, v_notes, NEW.id, NEW.client_profile_id)
      ON CONFLICT (rdv_id) WHERE rdv_id IS NOT NULL
      DO UPDATE SET titre=EXCLUDED.titre, date_debut=EXCLUDED.date_debut, animal_id=EXCLUDED.animal_id, notes=EXCLUDED.notes;
    END IF;
    -- Intervention : récupération de l'animal (2e événement), à l'heure réelle une fois faite.
    IF NEW.client_uid IS NOT NULL THEN
      DELETE FROM agenda_events WHERE couleur = 'recup:' || NEW.id::text;
      IF NEW.intervention_type IS NOT NULL AND COALESCE(NEW.sortie_le, NEW.heure_recuperation) IS NOT NULL THEN
        SELECT nom INTO v_animal FROM animaux WHERE id::text = NEW.animal_id::text;
        v_animal := COALESCE(NULLIF(v_animal, ''), NULLIF(NEW.animal_nom_manuel, ''), 'votre animal');
        INSERT INTO agenda_events (uid, titre, type, date_debut, duree_minutes, animal_id, notes, couleur, pro_profile_id)
        VALUES (NEW.client_uid,
          CASE WHEN NEW.sortie_le IS NOT NULL THEN 'Récupération de ' || v_animal || ' effectuée' ELSE 'Récupérer ' || v_animal END
            || ' — ' || COALESCE(pro_name, 'Professionnel'),
          'rdv', COALESCE(NEW.sortie_le, NEW.heure_recuperation), 15, NEW.animal_id,
          COALESCE(NULLIF(NEW.motif, ''), 'Intervention') || CASE WHEN NEW.sortie_le IS NOT NULL THEN ''
            ELSE E'\nHeure prévue : la clinique vous prévient quand votre animal est prêt.' END,
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

DROP TRIGGER IF EXISTS rdv_agenda_sync ON public.rdv;
CREATE TRIGGER rdv_agenda_sync AFTER UPDATE OF statut, date_heure, heure_recuperation, consignes_preop, motif, sortie_le ON public.rdv
  FOR EACH ROW EXECUTE FUNCTION public.sync_rdv_agenda();

-- Interventions déjà sorties : événement de récupération corrigé, puis RDV terminés
-- (sans demande d'avis : ce trigger ne se déclenche que sur sortie_le).
UPDATE agenda_events e
   SET titre = 'Récupération de ' || COALESCE(NULLIF(a.nom, ''), NULLIF(r.animal_nom_manuel, ''), 'votre animal') || ' effectuée'
         || COALESCE(' — ' || NULLIF(trim(COALESCE(up.nom, '')), ''), ''),
       date_debut = r.sortie_le,
       notes = COALESCE(NULLIF(r.motif, ''), 'Intervention')
  FROM rdv r
  LEFT JOIN animaux a ON a.id::text = r.animal_id::text
  LEFT JOIN user_profiles_complet up ON up.id::text = r.pro_profile_id
 WHERE e.couleur = 'recup:' || r.id::text
   AND r.intervention_type IS NOT NULL AND r.sortie_le IS NOT NULL;

UPDATE rdv SET statut = 'termine', termine_at = sortie_le
 WHERE intervention_type IS NOT NULL AND sortie_le IS NOT NULL AND statut = 'confirme';

COMMIT;
