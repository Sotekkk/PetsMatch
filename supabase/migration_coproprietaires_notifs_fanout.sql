-- Co-propriétaires : propagation des notifications liées à un animal
-- ============================================================================
-- Complément de migration_animaux_coproprietaires.sql.
-- L'agenda partagé (côté app + site) montre déjà à tous les co-propriétaires
-- les `agenda_events` liés à un animal co-possédé (RDV véto / comportementaliste
-- / ostéo, rappels vaccins/traitements, mise-bas…). Ce trigger complète le
-- dispositif : les NOTIFICATIONS portant un identifiant d'animal dans leur
-- payload sont recopiées pour chaque autre co-propriétaire actif.
--
-- Couverture : dépend de la présence de `animal_id` / `animalId` dans
-- `notifications.data`. Les émetteurs qui ne le renseignent pas encore ne sont
-- pas propagés (à normaliser au fil de l'eau).
-- ============================================================================

CREATE OR REPLACE FUNCTION fanout_notif_coproprietaires() RETURNS TRIGGER AS $$
DECLARE
  v_animal_id TEXT;
  v_co RECORD;
BEGIN
  -- Copie déjà propagée, ou notification interne à la copropriété → stop
  -- (évite toute récursion).
  IF (NEW.data ->> '_copro_fanout') = '1' OR NEW.type LIKE 'coproprio\_%' ESCAPE '\' THEN
    RETURN NEW;
  END IF;

  v_animal_id := COALESCE(
    NEW.data ->> 'animal_id',
    NEW.data ->> 'animalId',
    NEW.data ->> 'animalID'
  );
  IF v_animal_id IS NULL OR v_animal_id = '' THEN
    RETURN NEW;
  END IF;

  FOR v_co IN
    SELECT DISTINCT ap.uid_proprio, ap.profile_id_proprio
    FROM animaux_proprietes ap
    WHERE ap.animal_id = v_animal_id
      AND ap.date_fin IS NULL
      AND ap.statut = 'actif'
      AND ap.uid_proprio <> NEW.uid
  LOOP
    INSERT INTO notifications (
      uid, type, title, body, profile_type,
      profile_id, recipient_profile_id, data, read, created_at
    )
    VALUES (
      v_co.uid_proprio, NEW.type, NEW.title, NEW.body, 'particulier',
      v_co.profile_id_proprio, v_co.profile_id_proprio,
      COALESCE(NEW.data, '{}'::jsonb) || jsonb_build_object('_copro_fanout', '1'),
      false, now()
    );
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_fanout_notif_coproprietaires ON notifications;
CREATE TRIGGER trg_fanout_notif_coproprietaires
  AFTER INSERT ON notifications
  FOR EACH ROW EXECUTE FUNCTION fanout_notif_coproprietaires();
