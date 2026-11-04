-- Agenda de la famille : nom du PROFIL du RDV (04/11/2026).
-- sync_rdv_agenda prenait users.name_elevage (nom du compte) : un RDV pris
-- avec le profil « Vétérinaire test AB » apparaissait « RDV avec Pomsky de la
-- Luna » (nom de l'élevage du même compte). Le nom vient maintenant du profil
-- du RDV (user_profiles_complet.nom), sinon du compte. Reprend la fonction de
-- migration_rdv_bloc_bloquant.sql. Les événements existants sont corrigés.
-- Idempotent.

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

-- Événements déjà créés (dépôt, récupération) avec le nom du compte.
UPDATE agenda_events e
   SET titre = replace(e.titre, u.name_elevage, up.nom),
       notes = replace(coalesce(e.notes, ''), u.name_elevage, up.nom)
  FROM rdv r
  JOIN users u ON u.uid = r.pro_uid
  JOIN user_profiles_complet up ON up.id::text = r.pro_profile_id
 WHERE (e.rdv_id = r.id OR e.couleur = 'recup:' || r.id::text)
   AND e.uid IS DISTINCT FROM r.pro_uid
   AND NULLIF(trim(coalesce(up.nom, '')), '') IS NOT NULL
   AND NULLIF(trim(coalesce(u.name_elevage, '')), '') IS NOT NULL
   AND u.name_elevage <> up.nom
   AND (e.titre LIKE '%' || u.name_elevage || '%' OR e.notes LIKE '%' || u.name_elevage || '%');

-- Signataire des devis / contrats signés par le titulaire avec le nom du compte.
UPDATE documents_animaux d
   SET metadata = d.metadata || jsonb_build_object('signataire_eleveur_nom', up.nom)
  FROM user_profiles_complet up
 WHERE up.id::text = d.pro_profile_id::text
   AND d.metadata ? 'signataire_eleveur_nom'
   AND d.metadata ->> 'signataire_eleveur_uid' = d.uid_eleveur
   AND NULLIF(trim(coalesce(up.nom, '')), '') IS NOT NULL
   AND d.metadata ->> 'signataire_eleveur_nom' IS DISTINCT FROM up.nom
   AND d.metadata ->> 'signataire_eleveur_nom' = (SELECT name_elevage FROM users WHERE uid = d.uid_eleveur);

COMMIT;
