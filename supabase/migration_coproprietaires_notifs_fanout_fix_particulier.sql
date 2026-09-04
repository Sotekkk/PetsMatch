-- ─────────────────────────────────────────────────────────────────────────────
-- Fix : le fanout co-propriétaires (migration_coproprietaires_notifs_fanout.sql)
-- était censé ne concerner QUE les foyers particuliers (plusieurs personnes
-- copropriétaires d'un animal de compagnie), mais `animaux_proprietes` contient
-- aussi la ligne « principal » d'un animal d'élevage (profile_id_proprio =
-- profil éleveur). Sans filtre sur le type de profil du destinataire, le
-- trigger recopiait donc N'IMPORTE QUELLE notification portant un animal_id
-- (y compris des notifs internes pro→pro comme le miroir pension/véto) vers
-- l'éleveur lui-même, avec un profile_type toujours forcé à 'particulier' —
-- d'où des doublons « flag particulier » sur des animaux 100% élevage.
--
-- 2e garde-fou : le fanout ne doit jouer QUE quand la notif d'origine allait
-- déjà à un des propriétaires actifs de l'animal (partage entre co-proprios).
-- Sans ça, une notif adressée à un pro (véto, pension…) à propos d'un animal
-- particulier à propriétaire UNIQUE se recopiait quand même vers ce seul
-- propriétaire (son uid ≠ celui du pro) → doublon même sans copropriété.
-- Avec ce garde-fou : un animal à propriétaire unique n'a jamais de doublon,
-- quel que soit l'émetteur de la notif d'origine.
-- ─────────────────────────────────────────────────────────────────────────────

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

  -- La notif d'origine ne va pas à un propriétaire actif de cet animal
  -- (ex : notif interne pro→pro) → rien à partager entre co-propriétaires.
  IF NOT EXISTS (
    SELECT 1 FROM animaux_proprietes ap0
    WHERE ap0.animal_id = v_animal_id
      AND ap0.uid_proprio = NEW.uid
      AND ap0.date_fin IS NULL
      AND ap0.statut = 'actif'
  ) THEN
    RETURN NEW;
  END IF;

  FOR v_co IN
    SELECT DISTINCT ap.uid_proprio, ap.profile_id_proprio
    FROM animaux_proprietes ap
    JOIN user_profiles up ON up.id = ap.profile_id_proprio
    WHERE ap.animal_id = v_animal_id
      AND ap.date_fin IS NULL
      AND ap.statut = 'actif'
      AND ap.uid_proprio <> NEW.uid
      -- Scope : uniquement les foyers particuliers (copropriété familiale).
      -- Exclut la ligne « principal » d'un animal d'élevage (profil éleveur)
      -- et tout autre type de profil qui n'a rien à voir avec la copropriété.
      AND up.profile_type = 'particulier'
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
