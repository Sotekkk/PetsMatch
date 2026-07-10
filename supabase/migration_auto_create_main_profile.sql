-- À l'inscription, seule la table `users` recevait une ligne — `user_profiles`
-- n'était créée que si l'utilisateur visitait ensuite l'écran "ajouter un
-- profil", qui de plus ne renseigne jamais `is_main`. Résultat : un compte
-- fraîchement créé n'a aucune ligne `is_main=true`, ce qui casse silencieusement
-- ~90 lectures dans l'app et le site qui résolvent "le profil principal" via
-- `.eq('is_main', true)` sans repli.
--
-- Ce trigger crée automatiquement une ligne user_profiles (is_main=true) dès
-- l'insertion sur `users`, avec le profile_type déduit des colonnes déjà
-- connues à ce moment (is_association/is_elevage/is_pro+cat_pro). Si
-- l'utilisateur va ensuite sur "ajouter un profil" pour le même type,
-- l'upsert (onConflict: uid,profile_type) complète cette ligne au lieu d'en
-- créer une nouvelle — is_main reste intact car cet écran ne le touche jamais.

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

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_create_main_profile ON users;
CREATE TRIGGER trg_create_main_profile
  AFTER INSERT ON users
  FOR EACH ROW EXECUTE FUNCTION create_main_profile_on_signup();

-- Backfill défensif : comptes existants n'ayant aucune ligne user_profiles
INSERT INTO user_profiles (
  uid, profile_type, is_main,
  firstname, lastname, phone_number,
  nom, numero_elevage, siret, desc_entreprise, cat_pro, profession_pro,
  especes_elevees,
  adresse, rue, ville, code_postal, pays,
  rue_pro, ville_pro, code_postal_pro, pays_pro
)
SELECT
  u.uid,
  CASE
    WHEN u.is_association IS TRUE THEN 'association'
    WHEN u.is_elevage IS TRUE THEN 'eleveur'
    WHEN u.is_pro IS TRUE AND NULLIF(u.cat_pro, '') IS NOT NULL THEN u.cat_pro
    ELSE 'particulier'
  END,
  TRUE,
  u.firstname, u.lastname, u.phone_number,
  COALESCE(NULLIF(u.name_elevage, ''), NULLIF(trim(concat_ws(' ', u.firstname, u.lastname)), '')),
  u.numero_elevage, u.siret, u.desc_entreprise, u.cat_pro, u.profession_pro,
  u.especes_elevees,
  u.adress, u.rue, u.ville, u.code_postal, u.pays,
  u.rue_elevage, u.ville_elevage, u.code_postal_elevage, u.pays_elevage
FROM users u
WHERE NOT EXISTS (SELECT 1 FROM user_profiles p WHERE p.uid = u.uid)
ON CONFLICT (uid, profile_type) DO NOTHING;
