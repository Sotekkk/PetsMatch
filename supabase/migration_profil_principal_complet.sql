-- ════════════════════════════════════════════════════════════════════════
-- Profil principal créé à l'inscription : reprendre TOUT ce qui a été saisi.
--
-- create_main_profile_on_signup (trigger sur users) ne recopiait pas : RNA,
-- agrément, capacité, espèces accueillies (association), photo / logo,
-- bannière, téléphone (phone / telephone lus par les écrans), GPS, ni
-- l'adresse de l'établissement dans adresse / rue / ville / code_postal du
-- profil (seulement dans *_pro). Résultat : l'écran « configurer mon
-- compte » redemandait nom, RNA, adresse, photo, espèces (ex. « tortue »
-- perdue). Règle projet : données d'inscription = profil d'édition.
--
-- RNA : référence unique user_profiles.rna (l'appli écrivait users.rna, le
-- site et l'écran d'édition user_profiles.ordre_veterinaire, l'admin lit
-- rna). Rattrapage : rna ← ordre_veterinaire pour les associations.
-- Rattrapage général : profils principaux non particulier — champs VIDES
-- seulement, depuis users (jamais d'écrasement d'une valeur existante).
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

CREATE OR REPLACE FUNCTION public.create_main_profile_on_signup()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_profile_type text;
  v_pro boolean;
  v_especes text[];
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
  v_pro := v_profile_type <> 'particulier';

  -- Espèces accueillies (association) : jsonb ["chien","tortue"] → text[]
  IF jsonb_typeof(NEW.especes_accueillies) = 'array' THEN
    SELECT array_agg(e) INTO v_especes FROM jsonb_array_elements_text(NEW.especes_accueillies) e;
  END IF;

  BEGIN
    INSERT INTO user_profiles (
      uid, profile_type, is_main,
      firstname, lastname, phone_number, phone, telephone,
      nom, numero_elevage, siret, desc_entreprise, cat_pro, profession_pro,
      especes_elevees, especes_accueil, rna, agrement_prefectoral, capacite_accueil,
      avatar_url, banner_url, lat, lng,
      adresse, rue, ville, code_postal, pays,
      rue_pro, ville_pro, code_postal_pro, pays_pro,
      statut_pro, validation_status, is_validate
    ) VALUES (
      NEW.uid, v_profile_type, TRUE,
      NEW.firstname, NEW.lastname, NEW.phone_number, NEW.phone_number, NEW.phone_number,
      COALESCE(NULLIF(NEW.name_elevage, ''), NULLIF(trim(concat_ws(' ', NEW.firstname, NEW.lastname)), '')),
      NEW.numero_elevage, NEW.siret, NEW.desc_entreprise, NEW.cat_pro, NEW.profession_pro,
      NEW.especes_elevees,
      CASE WHEN v_profile_type = 'association' THEN v_especes END,
      NULLIF(NEW.rna, ''), NULLIF(NEW.agrement_prefectoral, ''),
      CASE WHEN v_profile_type = 'association' THEN NEW.capacite_accueil END,
      CASE WHEN v_pro THEN COALESCE(NULLIF(NEW.profile_picture_url_elevage, ''), NULLIF(NEW.profile_picture_url, ''))
           ELSE NULLIF(NEW.profile_picture_url, '') END,
      NULLIF(NEW.banner_url, ''), NEW.lat, NEW.lng,
      -- Pro / élevage / association : l'adresse du profil = celle de l'établissement
      CASE WHEN v_pro THEN COALESCE(NULLIF(NEW.adress_elevage, ''), NEW.adress) ELSE NEW.adress END,
      CASE WHEN v_pro THEN COALESCE(NULLIF(NEW.rue_elevage, ''), NEW.rue) ELSE NEW.rue END,
      CASE WHEN v_pro THEN COALESCE(NULLIF(NEW.ville_elevage, ''), NEW.ville) ELSE NEW.ville END,
      CASE WHEN v_pro THEN COALESCE(NULLIF(NEW.code_postal_elevage, ''), NEW.code_postal) ELSE NEW.code_postal END,
      CASE WHEN v_pro THEN COALESCE(NULLIF(NEW.pays_elevage, ''), NEW.pays) ELSE NEW.pays END,
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
  IF v_pro THEN
    BEGIN
      INSERT INTO user_profiles (
        uid, profile_type, is_main, firstname, lastname, phone_number,
        avatar_url, statut_pro, validation_status, is_validate
      )
      VALUES (
        NEW.uid, 'particulier', FALSE, NEW.firstname, NEW.lastname, NEW.phone_number,
        NULLIF(NEW.profile_picture_url, ''), 'na', 'auto_validated', TRUE
      )
      ON CONFLICT (uid, profile_type) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN NEW;
END;
$function$;

-- ── Rattrapage : RNA rangé dans ordre_veterinaire (site / écran d'édition) ──
UPDATE user_profiles SET rna = ordre_veterinaire
WHERE profile_type = 'association' AND NULLIF(rna, '') IS NULL AND NULLIF(ordre_veterinaire, '') IS NOT NULL;

-- ── Rattrapage : profils principaux non particulier, champs VIDES ──────────
UPDATE user_profiles up SET
  rna                  = COALESCE(NULLIF(up.rna, ''), NULLIF(u.rna, '')),
  agrement_prefectoral = COALESCE(NULLIF(up.agrement_prefectoral, ''), NULLIF(u.agrement_prefectoral, '')),
  capacite_accueil     = CASE WHEN up.profile_type = 'association' THEN COALESCE(NULLIF(up.capacite_accueil, 0), u.capacite_accueil) ELSE up.capacite_accueil END,
  especes_accueil      = CASE WHEN up.profile_type = 'association' AND COALESCE(cardinality(up.especes_accueil), 0) = 0
                                AND jsonb_typeof(u.especes_accueillies) = 'array'
                              THEN ARRAY(SELECT jsonb_array_elements_text(u.especes_accueillies))
                              ELSE up.especes_accueil END,
  avatar_url           = COALESCE(NULLIF(up.avatar_url, ''), NULLIF(u.profile_picture_url_elevage, ''), NULLIF(u.profile_picture_url, '')),
  banner_url           = COALESCE(NULLIF(up.banner_url, ''), NULLIF(u.banner_url, '')),
  lat                  = COALESCE(up.lat, u.lat),
  lng                  = COALESCE(up.lng, u.lng),
  phone                = COALESCE(NULLIF(up.phone, ''), NULLIF(u.phone_number, '')),
  telephone            = COALESCE(NULLIF(up.telephone, ''), NULLIF(u.phone_number, '')),
  adresse              = COALESCE(NULLIF(up.adresse, ''), NULLIF(u.adress_elevage, '')),
  rue                  = COALESCE(NULLIF(up.rue, ''), NULLIF(u.rue_elevage, '')),
  ville                = COALESCE(NULLIF(up.ville, ''), NULLIF(u.ville_elevage, '')),
  code_postal          = COALESCE(NULLIF(up.code_postal, ''), NULLIF(u.code_postal_elevage, ''))
FROM users u
WHERE u.uid = up.uid AND up.is_main AND up.profile_type <> 'particulier';

COMMIT;
