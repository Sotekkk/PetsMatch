-- Fix : à l'inscription, un profil PARTICULIER était créé avec les valeurs par
-- défaut des colonnes de validation pro :
--   user_profiles.statut_pro        DEFAULT 'en_attente'
--   user_profiles.validation_status DEFAULT 'pending'
--   user_profiles.is_validate       DEFAULT false
-- create_main_profile_on_signup() ne les surchargeait pas → tout nouveau
-- particulier ressortait « En attente » (file de validation admin, section
-- « Profil professionnel »), alors qu'un particulier n'a rien à faire valider.
-- Les anciens particuliers étaient corrects uniquement grâce aux backfills
-- ponctuels des migrations v2_01 (statut_pro='na') et v2_07 (validation_status
-- ='auto_validated') — rien ne le faisait pour les inscriptions suivantes.
--
-- Correctif : la fonction pose explicitement les 3 colonnes selon le type.
--   particulier            → statut_pro='na',  validation_status='auto_validated', is_validate=true
--   eleveur/association/pro → statut_pro='en_attente', validation_status='pending', is_validate=false
-- ============================================================================

CREATE OR REPLACE FUNCTION create_main_profile_on_signup()
RETURNS trigger AS $$
DECLARE
  v_profile_type text;
BEGIN
  -- Idempotence : ne rien faire si une ligne existe déjà pour cet uid
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
      rue_pro, ville_pro, code_postal_pro, pays_pro,
      statut_pro, validation_status, is_validate
    ) VALUES (
      NEW.uid, v_profile_type, TRUE,
      NEW.firstname, NEW.lastname, NEW.phone_number,
      COALESCE(NULLIF(NEW.name_elevage, ''), NULLIF(trim(concat_ws(' ', NEW.firstname, NEW.lastname)), '')),
      NEW.numero_elevage, NEW.siret, NEW.desc_entreprise, NEW.cat_pro, NEW.profession_pro,
      NEW.especes_elevees,
      NEW.adress, NEW.rue, NEW.ville, NEW.code_postal, NEW.pays,
      NEW.rue_elevage, NEW.ville_elevage, NEW.code_postal_elevage, NEW.pays_elevage,
      CASE WHEN v_profile_type = 'particulier' THEN 'na'             ELSE 'en_attente' END,
      CASE WHEN v_profile_type = 'particulier' THEN 'auto_validated' ELSE 'pending'    END,
      (v_profile_type = 'particulier')
    )
    ON CONFLICT (uid, profile_type) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      INSERT INTO user_profiles (
        uid, profile_type, is_main, firstname, lastname, phone_number,
        statut_pro, validation_status, is_validate
      )
      VALUES (
        NEW.uid, 'particulier', TRUE, NEW.firstname, NEW.lastname, NEW.phone_number,
        'na', 'auto_validated', TRUE
      )
      ON CONFLICT (uid, profile_type) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END;

  -- Profil principal non-particulier → profil particulier secondaire d'ancrage.
  IF v_profile_type <> 'particulier' THEN
    BEGIN
      INSERT INTO user_profiles (
        uid, profile_type, is_main, firstname, lastname, phone_number,
        statut_pro, validation_status, is_validate
      )
      VALUES (
        NEW.uid, 'particulier', FALSE, NEW.firstname, NEW.lastname, NEW.phone_number,
        'na', 'auto_validated', TRUE
      )
      ON CONFLICT (uid, profile_type) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Ré-assertion du trigger (no-op si déjà en place — CREATE OR REPLACE garde le
-- binding, mais on le recrée par sécurité).
DROP TRIGGER IF EXISTS trg_create_main_profile ON users;
CREATE TRIGGER trg_create_main_profile
  AFTER INSERT ON users
  FOR EACH ROW EXECUTE FUNCTION create_main_profile_on_signup();

-- ── Backfill : particuliers déjà créés avec les mauvaises valeurs ────────────
UPDATE user_profiles
SET statut_pro        = 'na',
    validation_status = 'auto_validated',
    is_validate       = TRUE
WHERE profile_type = 'particulier'
  AND (statut_pro IN ('en_attente', 'pending') OR validation_status = 'pending');

-- Nettoie les alertes admin ouvertes à tort sur des profils particuliers.
UPDATE admin_alerts a
SET status = 'dismissed', resolved_at = now(), resolved_by = 'auto',
    resolved_note = 'Profil particulier — aucune validation requise'
WHERE a.status = 'pending'
  AND EXISTS (
    SELECT 1 FROM user_profiles up
    WHERE up.id = a.profile_id AND up.profile_type = 'particulier'
  );
