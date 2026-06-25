-- ============================================================
-- PetsMatch V2 — Phase 1 : user_profiles source unique
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================
-- Colonnes déjà existantes dans user_profiles (ne pas re-ajouter) :
--   id, uid, profile_type, cat_pro, name_elevage, avatar_url,
--   profile_label, statut_pro, rayon_intervention, especes_acceptees,
--   certifications, profession_pro, horaires, accept_new_clients,
--   banner_url, tarifs, instagram, facebook, durees_motifs,
--   lat, lng, latitude, longitude, is_pro, desc_entreprise,
--   departement, region, ville_elevage, code_postal_elevage,
--   rue_elevage, adress_elevage, pays_elevage,
--   ville, description, adresse, telephone, site_web,
--   ordre_veterinaire, siret, kbis_url, acaced_doc_url,
--   especes_accueil, capacite_accueil, rue, code_postal, pays, phone
-- ============================================================

-- ─── ÉTAPE 0 : Renommages sémantiques ───────────────────────
-- name_elevage → nom (un profil vétérinaire/asso/particulier n'est pas un "élevage")
-- Dans users, name_elevage reste (spécifique à l'éleveur)

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'user_profiles' AND column_name = 'name_elevage'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'user_profiles' AND column_name = 'nom'
  ) THEN
    ALTER TABLE user_profiles RENAME COLUMN name_elevage TO nom;
  END IF;
END $$;

-- ─── ÉTAPE 0b : Conversions de types ────────────────────────
-- especes_elevees TEXT[] → JSONB (pour stocker [{espece, races[]}])

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'user_profiles'
      AND column_name = 'especes_elevees'
      AND data_type = 'ARRAY'
  ) THEN
    ALTER TABLE user_profiles ALTER COLUMN especes_elevees DROP DEFAULT;
    ALTER TABLE user_profiles
      ALTER COLUMN especes_elevees TYPE JSONB
      USING COALESCE(to_jsonb(especes_elevees), '[]'::jsonb);
    ALTER TABLE user_profiles ALTER COLUMN especes_elevees SET DEFAULT '[]'::jsonb;
  END IF;
END $$;

-- ─── ÉTAPE 1 : Colonnes manquantes sur user_profiles ────────

ALTER TABLE user_profiles
  -- Profil principal
  ADD COLUMN IF NOT EXISTS is_main                 BOOLEAN NOT NULL DEFAULT FALSE,
  -- Identité
  ADD COLUMN IF NOT EXISTS firstname               TEXT,
  ADD COLUMN IF NOT EXISTS lastname                TEXT,
  ADD COLUMN IF NOT EXISTS phone_number            TEXT,
  ADD COLUMN IF NOT EXISTS email_contact           TEXT,
  ADD COLUMN IF NOT EXISTS profile_picture_url_pro TEXT,   -- logo élevage / établissement distinct
  -- Adresse pro si différente de la principale
  ADD COLUMN IF NOT EXISTS rue_pro                 TEXT,
  ADD COLUMN IF NOT EXISTS ville_pro               TEXT,
  ADD COLUMN IF NOT EXISTS code_postal_pro         TEXT,
  ADD COLUMN IF NOT EXISTS departement_pro         TEXT,
  ADD COLUMN IF NOT EXISTS region_pro              TEXT,
  ADD COLUMN IF NOT EXISTS pays_pro                TEXT,
  ADD COLUMN IF NOT EXISTS lat_pro                 FLOAT8,
  ADD COLUMN IF NOT EXISTS lng_pro                 FLOAT8,
  -- Validation admin (par profil)
  ADD COLUMN IF NOT EXISTS is_validate             BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS rejection_reason        TEXT,
  -- Documents pro
  ADD COLUMN IF NOT EXISTS numero_tva              TEXT,
  ADD COLUMN IF NOT EXISTS acaced                  TEXT,   -- numéro ACACED (format libre)
  ADD COLUMN IF NOT EXISTS acaced_date_obtention   DATE,
  ADD COLUMN IF NOT EXISTS acaced_date_renewal     DATE,
  ADD COLUMN IF NOT EXISTS diplome_url             TEXT,   -- comportementaliste, photo, para-médical
  -- Éleveur
  ADD COLUMN IF NOT EXISTS numero_elevage          TEXT,
  ADD COLUMN IF NOT EXISTS especes_elevees         JSONB DEFAULT '[]',
  -- Association
  ADD COLUMN IF NOT EXISTS rna                     TEXT,
  ADD COLUMN IF NOT EXISTS agrement_prefectoral    TEXT,
  -- Vétérinaire / para-médical
  ADD COLUMN IF NOT EXISTS numero_ordre            TEXT,   -- numéro ordre vétérinaire
  ADD COLUMN IF NOT EXISTS nom_cabinet             TEXT,
  -- Pension / Petsitter / Promeneur / Maréchal-ferrant
  ADD COLUMN IF NOT EXISTS capacite_max            INTEGER,
  ADD COLUMN IF NOT EXISTS deplacement             BOOLEAN,
  ADD COLUMN IF NOT EXISTS numero_etablissement    TEXT,   -- numéro DDPP
  ADD COLUMN IF NOT EXISTS type_hebergement        TEXT,   -- 'chenil'|'chatterie'|'mixte'|'pension_equestre'
  -- Particulier
  ADD COLUMN IF NOT EXISTS date_of_birth           DATE,
  -- Notifications
  ADD COLUMN IF NOT EXISTS fcm_token               TEXT,
  ADD COLUMN IF NOT EXISTS apns_token              TEXT,
  -- Abonnement
  ADD COLUMN IF NOT EXISTS is_premium              BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS stripe_customer_id      TEXT,
  ADD COLUMN IF NOT EXISTS cgu_accepted_at         TIMESTAMPTZ;

-- Contrainte CHECK sur profile_type (étend les valeurs existantes)
ALTER TABLE user_profiles DROP CONSTRAINT IF EXISTS user_profiles_profile_type_check;
ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_profile_type_check
  CHECK (profile_type IS NULL OR profile_type IN (
    'particulier','eleveur','association','veterinaire',
    'pension','education','petsitter','promeneur',
    'photographe','para_medical','marechal_ferrant',
    'petfriendly','partenaire',
    -- anciennes valeurs (compatibilité V1)
    'educateur','comportementaliste','garde','veto','sante'
  ));

-- Contrainte CHECK sur statut_pro (V1 + V2)
ALTER TABLE user_profiles DROP CONSTRAINT IF EXISTS user_profiles_statut_pro_check;
ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_statut_pro_check
  CHECK (statut_pro IN (
    'na','pending','validated','rejected',   -- V2
    'en_attente','actif','refuse'            -- V1 (compatibilité)
  ));

-- Index unicité : un seul profil is_main par uid
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_profiles_main_per_uid
  ON user_profiles (uid) WHERE is_main = TRUE;

-- ─── ÉTAPE 2 : Normaliser les valeurs de profile_type ────────

UPDATE user_profiles
SET profile_type = CASE
  WHEN profile_type = 'educateur'         THEN 'education'
  WHEN profile_type = 'comportementaliste' THEN 'education'
  WHEN profile_type = 'veto'              THEN 'veterinaire'
  WHEN profile_type = 'garde'             THEN 'petsitter'
  ELSE profile_type
END
WHERE profile_type IN ('educateur','comportementaliste','veto','garde');

-- ─── ÉTAPE 3 : Créer les profils principaux depuis users ─────
-- Un profil is_main=TRUE par utilisateur

INSERT INTO user_profiles (
  uid,
  profile_type,
  cat_pro,
  is_main,
  nom,
  firstname,
  lastname,
  phone_number,
  email_contact,
  avatar_url,
  profile_picture_url_pro,
  desc_entreprise,
  adresse,
  rue,
  ville,
  code_postal,
  departement,
  region,
  pays,
  lat,
  lng,
  rue_pro,
  ville_pro,
  code_postal_pro,
  pays_pro,
  instagram,
  facebook,
  site_web,
  is_validate,
  statut_pro,
  rejection_reason,
  siret,
  numero_tva,
  kbis_url,
  acaced,
  acaced_date_obtention,
  acaced_doc_url,
  certifications,
  numero_elevage,
  especes_elevees,
  especes_accueil,
  capacite_accueil,
  especes_acceptees,
  date_of_birth,
  fcm_token,
  apns_token,
  is_premium,
  horaires,
  tarifs,
  durees_motifs,
  created_at
)
SELECT
  u.uid,

  -- profile_type V2
  CASE
    WHEN COALESCE(u.is_elevage, FALSE) AND NOT COALESCE(u.is_association, FALSE) THEN 'eleveur'
    WHEN COALESCE(u.is_association, FALSE)                                        THEN 'association'
    WHEN u.cat_pro IN (
      'particulier','eleveur','association','veterinaire',
      'pension','education','petsitter','promeneur',
      'photographe','para_medical','marechal_ferrant',
      'petfriendly','partenaire'
    )                                                                             THEN u.cat_pro
    WHEN u.cat_pro IN ('educateur','comportementaliste')                          THEN 'education'
    WHEN u.cat_pro = 'veto'                                                       THEN 'veterinaire'
    WHEN u.cat_pro = 'garde'                                                      THEN 'petsitter'
    WHEN COALESCE(u.is_pro, FALSE)                                                THEN COALESCE(u.cat_pro,'particulier')
    ELSE 'particulier'
  END,

  -- cat_pro (compatibilité V1)
  COALESCE(u.cat_pro, 'particulier'),
  TRUE,  -- is_main

  -- name_elevage : nom structure si éleveur/pro, sinon prénom+nom
  CASE
    WHEN u.name_elevage IS NOT NULL AND u.name_elevage != '' THEN u.name_elevage
    ELSE NULLIF(TRIM(COALESCE(u.firstname,'') || ' ' || COALESCE(u.lastname,'')), '')
  END,

  u.firstname,
  u.lastname,
  u.phone_number,
  u.email,                          -- email_contact
  u.profile_picture_url,            -- avatar_url
  u.profile_picture_url_elevage,    -- profile_picture_url_pro (logo élevage)
  u.desc_entreprise,
  u.adress,                         -- adresse
  u.rue,
  u.ville,
  u.code_postal,
  NULL,                             -- departement (non dispo sur users)
  NULL,                             -- region
  COALESCE(u.pays, 'France'),
  u.lat,
  u.lng,
  u.rue_elevage,                    -- rue_pro
  u.ville_elevage,                  -- ville_pro
  u.code_postal_elevage,            -- code_postal_pro
  u.pays_elevage,                   -- pays_pro
  u.instagram,
  u.facebook,
  u.site_web,
  COALESCE(u.is_validate, FALSE),

  -- statut_pro V2
  CASE
    WHEN NOT COALESCE(u.is_elevage,FALSE)
     AND NOT COALESCE(u.is_association,FALSE)
     AND NOT COALESCE(u.is_pro,FALSE)        THEN 'na'
    WHEN u.statut_pro = 'actif'              THEN 'validated'
    WHEN u.statut_pro = 'en_attente'         THEN 'pending'
    WHEN u.statut_pro = 'refuse'             THEN 'rejected'
    WHEN COALESCE(u.is_validate, FALSE)      THEN 'validated'
    ELSE 'pending'
  END,

  u.rejection_reason,
  u.siret,
  u.numero_tva,
  u.kbis_url,
  u.acaced_numero,                  -- acaced (numéro)
  u.acaced_date_obtention,
  u.acaced_doc_url,
  COALESCE(u.certifications, '[]'),
  u.numero_elevage,
  COALESCE(u.especes_elevees, '[]'),
  NULL,                             -- especes_accueil (spécifique association)
  NULL,                             -- capacite_accueil
  CASE
    WHEN u.especes_acceptees IS NOT NULL AND jsonb_typeof(u.especes_acceptees) = 'array'
    THEN ARRAY(SELECT jsonb_array_elements_text(u.especes_acceptees))
    ELSE NULL::TEXT[]
  END,
  u.date_of_birth,
  u.fcm_token,
  u.apns_token,
  COALESCE(u.is_premium, FALSE),
  '{}',                             -- horaires
  NULL,                             -- tarifs
  '{}',                             -- durees_motifs
  u.created_at

FROM users u
WHERE NOT EXISTS (
  SELECT 1 FROM user_profiles up
  WHERE up.uid = u.uid AND up.is_main = TRUE
);

-- ─── ÉTAPE 4 : Profil particulier secondaire pour tous les pros

INSERT INTO user_profiles (
  uid, profile_type, cat_pro, is_main,
  nom, firstname, lastname,
  phone_number, email_contact, avatar_url,
  adresse, rue, ville, code_postal, pays, lat, lng,
  instagram, facebook, site_web,
  is_validate, statut_pro,
  date_of_birth, fcm_token, apns_token,
  certifications, horaires, durees_motifs,
  created_at
)
SELECT
  u.uid, 'particulier', 'particulier', FALSE,
  NULLIF(TRIM(COALESCE(u.firstname,'') || ' ' || COALESCE(u.lastname,'')), ''),
  u.firstname, u.lastname,
  u.phone_number, u.email, u.profile_picture_url,
  u.adress, u.rue, u.ville, u.code_postal,
  COALESCE(u.pays,'France'), u.lat, u.lng,
  u.instagram, u.facebook, u.site_web,
  TRUE, 'na',
  u.date_of_birth, u.fcm_token, u.apns_token,
  '[]', '{}', '{}',
  u.created_at
FROM users u
WHERE (
  COALESCE(u.is_elevage, FALSE)
  OR COALESCE(u.is_association, FALSE)
  OR COALESCE(u.is_pro, FALSE)
)
AND NOT EXISTS (
  SELECT 1 FROM user_profiles up
  WHERE up.uid = u.uid
    AND up.profile_type = 'particulier'
    AND up.is_main = FALSE
);

-- ─── ÉTAPE 5 : Relier users.profile_id au profil principal ──

UPDATE users u
SET profile_id = up.id
FROM user_profiles up
WHERE up.uid = u.uid
  AND up.is_main = TRUE
  AND (u.profile_id IS NULL OR u.profile_id != up.id);

-- ─── ÉTAPE 6 : Index ────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_user_profiles_uid
  ON user_profiles (uid);
CREATE INDEX IF NOT EXISTS idx_user_profiles_type
  ON user_profiles (profile_type);
CREATE INDEX IF NOT EXISTS idx_user_profiles_statut
  ON user_profiles (statut_pro)
  WHERE statut_pro IN ('pending','en_attente');

-- ─── VÉRIFICATION ────────────────────────────────────────────

SELECT
  COALESCE(profile_type, 'non défini') AS type,
  COUNT(*) FILTER (WHERE is_main = TRUE)  AS profils_principaux,
  COUNT(*) FILTER (WHERE is_main = FALSE) AS profils_secondaires
FROM user_profiles
GROUP BY profile_type
ORDER BY profile_type;
