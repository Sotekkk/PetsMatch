-- Règle métier : un compte a TOUJOURS un profil particulier, même s'il s'est
-- inscrit directement en pro/éleveur/association. C'est ce profil particulier
-- (unique par uid, cf. contrainte user_profiles_uid_profile_type_key) qui sert
-- de point d'ancrage pour tout ce qui concerne l'employé en tant que personne :
-- employe_profile_id, permissions, tâches assignées, agenda, notifications.
-- Le menu "Mes Employeurs" / "Mes Associations" (bénévole) ne doit être visible
-- que sur ce profil particulier — jamais sur les profils pro/éleveur/association.
--
-- Avant cette migration, create_main_profile_on_signup() (voir
-- migration_auto_create_main_profile.sql) ne créait qu'UN SEUL profil, du type
-- déduit de is_association/is_elevage/is_pro. Un compte inscrit directement en
-- pro n'avait donc aucun profil particulier, ce qui forçait tout le code
-- (nav drawers, MesEmployeursPage, notifications…) à retomber sur un fallback
-- "uid brut" qui ignore le profil actif — d'où la fuite cross-profil observée
-- (le même employeur visible depuis n'importe quel profil du compte).

CREATE OR REPLACE FUNCTION create_main_profile_on_signup()
RETURNS trigger AS $$
DECLARE
  v_profile_type text;
BEGIN
  -- Idempotence : ne rien faire si une ligne existe déjà pour cet uid
  -- (ré-appel de registerElevage/createProfile, ex. flux "email déjà utilisé")
  IF EXISTS (SELECT 1 FROM user_profiles WHERE uid = NEW.uid) THEN
    RETURN NEW;
  END IF;

  IF NEW.is_association IS TRUE THEN
    v_profile_type := 'association';
  ELSIF NEW.is_elevage IS TRUE THEN
    v_profile_type := 'eleveur';
  ELSIF NEW.is_pro IS TRUE AND NULLIF(NEW.cat_pro, '') IS NOT NULL THEN
    v_profile_type := NEW.cat_pro;
  ELSE
    v_profile_type := 'particulier';
  END IF;

  BEGIN
    INSERT INTO user_profiles (
      uid, profile_type, is_main,
      firstname, lastname, phone_number,
      nom, numero_elevage, siret, desc_entreprise, cat_pro, profession_pro,
      especes_elevees,
      adresse, rue, ville, code_postal, pays,
      rue_pro, ville_pro, code_postal_pro, pays_pro
    ) VALUES (
      NEW.uid, v_profile_type, TRUE,
      NEW.firstname, NEW.lastname, NEW.phone_number,
      COALESCE(NULLIF(NEW.name_elevage, ''), NULLIF(trim(concat_ws(' ', NEW.firstname, NEW.lastname)), '')),
      NEW.numero_elevage, NEW.siret, NEW.desc_entreprise, NEW.cat_pro, NEW.profession_pro,
      NEW.especes_elevees,
      NEW.adress, NEW.rue, NEW.ville, NEW.code_postal, NEW.pays,
      NEW.rue_elevage, NEW.ville_elevage, NEW.code_postal_elevage, NEW.pays_elevage
    )
    ON CONFLICT (uid, profile_type) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    -- Repli : profile_type déduit invalide ou tout autre souci imprévu.
    -- Ne jamais bloquer l'inscription — au pire, créer une ligne minimale.
    BEGIN
      INSERT INTO user_profiles (uid, profile_type, is_main, firstname, lastname, phone_number)
      VALUES (NEW.uid, 'particulier', TRUE, NEW.firstname, NEW.lastname, NEW.phone_number)
      ON CONFLICT (uid, profile_type) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN
      NULL; -- dernier recours : ne jamais faire échouer l'INSERT sur users
    END;
  END;

  -- Le profil principal ci-dessus n'est pas de type particulier (compte
  -- inscrit directement en pro/éleveur/association) → on crée en plus un
  -- profil particulier secondaire (is_main = FALSE), pour que l'utilisateur
  -- ait toujours un profil particulier auquel rattacher ses relations
  -- d'employé/bénévole, ses tâches assignées et son agenda personnel.
  IF v_profile_type <> 'particulier' THEN
    BEGIN
      INSERT INTO user_profiles (uid, profile_type, is_main, firstname, lastname, phone_number)
      VALUES (NEW.uid, 'particulier', FALSE, NEW.firstname, NEW.lastname, NEW.phone_number)
      ON CONFLICT (uid, profile_type) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Backfill défensif : comptes existants ayant un profil principal non-particulier
-- mais aucun profil particulier du tout.
INSERT INTO user_profiles (uid, profile_type, is_main, firstname, lastname, phone_number)
SELECT DISTINCT
  up.uid, 'particulier', FALSE, up.firstname, up.lastname, up.phone_number
FROM user_profiles up
WHERE up.is_main = TRUE
  AND up.profile_type <> 'particulier'
  AND NOT EXISTS (
    SELECT 1 FROM user_profiles p2
    WHERE p2.uid = up.uid AND p2.profile_type = 'particulier'
  )
ON CONFLICT (uid, profile_type) DO NOTHING;
