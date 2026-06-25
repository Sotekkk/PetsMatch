-- ============================================================
-- PetsMatch V2 — Phase 1 : user_profiles source unique
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

-- ─── ÉTAPE 1 : Colonnes manquantes sur user_profiles ────────

ALTER TABLE user_profiles
  -- Identifiant du profil principal
  ADD COLUMN IF NOT EXISTS is_main            BOOLEAN NOT NULL DEFAULT FALSE,
  -- Type étendu (complète cat_pro existant)
  ADD COLUMN IF NOT EXISTS type_profil        TEXT,
  -- Identité
  ADD COLUMN IF NOT EXISTS firstname          TEXT,
  ADD COLUMN IF NOT EXISTS lastname           TEXT,
  ADD COLUMN IF NOT EXISTS name_pro           TEXT,   -- nom structure (élevage/cabinet/asso)
  ADD COLUMN IF NOT EXISTS phone_number       TEXT,
  ADD COLUMN IF NOT EXISTS email_contact      TEXT,
  ADD COLUMN IF NOT EXISTS profile_picture_url     TEXT,
  ADD COLUMN IF NOT EXISTS profile_picture_url_pro TEXT, -- logo élevage / établissement
  -- Adresse pro si différente de la principale
  ADD COLUMN IF NOT EXISTS rue_pro            TEXT,
  ADD COLUMN IF NOT EXISTS ville_pro          TEXT,
  ADD COLUMN IF NOT EXISTS code_postal_pro    TEXT,
  ADD COLUMN IF NOT EXISTS departement_pro    TEXT,
  ADD COLUMN IF NOT EXISTS region_pro         TEXT,
  ADD COLUMN IF NOT EXISTS pays_pro           TEXT,
  ADD COLUMN IF NOT EXISTS lat_pro            FLOAT8,
  ADD COLUMN IF NOT EXISTS lng_pro            FLOAT8,
  -- Validation admin (par profil)
  ADD COLUMN IF NOT EXISTS is_validate        BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS rejection_reason   TEXT,
  -- Documents pro communs
  ADD COLUMN IF NOT EXISTS numero_tva         TEXT,
  ADD COLUMN IF NOT EXISTS acaced             TEXT,   -- numéro ACACED (format libre)
  ADD COLUMN IF NOT EXISTS acaced_date_obtention DATE,
  ADD COLUMN IF NOT EXISTS acaced_date_renewal   DATE,
  ADD COLUMN IF NOT EXISTS diplome_url        TEXT,   -- comportementaliste, photo, para-médical
  -- Éleveur
  ADD COLUMN IF NOT EXISTS numero_elevage     TEXT,
  ADD COLUMN IF NOT EXISTS especes_elevees    JSONB DEFAULT '[]',
  -- Association
  ADD COLUMN IF NOT EXISTS rna                TEXT,
  ADD COLUMN IF NOT EXISTS agrement_prefectoral TEXT,
  -- Vétérinaire / para-médical
  ADD COLUMN IF NOT EXISTS numero_ordre       TEXT,   -- numéro d'ordre vétérinaire
  ADD COLUMN IF NOT EXISTS nom_cabinet        TEXT,
  -- Pension / Petsitter / Promeneur / Maréchal-ferrant
  ADD COLUMN IF NOT EXISTS capacite_max       INTEGER,
  ADD COLUMN IF NOT EXISTS deplacement        BOOLEAN,
  ADD COLUMN IF NOT EXISTS numero_etablissement TEXT,  -- numéro DDPP
  ADD COLUMN IF NOT EXISTS type_hebergement   TEXT,   -- 'chenil'|'chatterie'|'mixte'|'pension_equestre'
  -- Particulier
  ADD COLUMN IF NOT EXISTS date_of_birth      DATE,
  -- Notifications
  ADD COLUMN IF NOT EXISTS fcm_token          TEXT,
  ADD COLUMN IF NOT EXISTS apns_token         TEXT,
  -- Abonnement
  ADD COLUMN IF NOT EXISTS is_premium         BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT,
  ADD COLUMN IF NOT EXISTS cgu_accepted_at    TIMESTAMPTZ;

-- Contrainte CHECK sur type_profil (tous les types V2)
ALTER TABLE user_profiles DROP CONSTRAINT IF EXISTS user_profiles_type_profil_check;
ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_type_profil_check
  CHECK (type_profil IS NULL OR type_profil IN (
    'particulier','eleveur','association','veterinaire',
    'pension','education','petsitter','promeneur',
    'photographe','para_medical','marechal_ferrant',
    'petfriendly','partenaire'
  ));

-- Contrainte CHECK sur statut_pro (harmonisation V1 + V2)
ALTER TABLE user_profiles DROP CONSTRAINT IF EXISTS user_profiles_statut_pro_check;
ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_statut_pro_check
  CHECK (statut_pro IN (
    'na','pending','validated','rejected',   -- V2
    'en_attente','actif','refuse'            -- V1 (compatibilité)
  ));

-- Index unicité : un seul profil is_main par utilisateur
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_profiles_main_per_uid
  ON user_profiles (uid) WHERE is_main = TRUE;

-- ─── ÉTAPE 2 : Peupler type_profil depuis cat_pro existant ──

UPDATE user_profiles
SET type_profil = CASE
  WHEN cat_pro IN (
    'particulier','eleveur','association','veterinaire',
    'pension','education','petsitter','promeneur',
    'photographe','para_medical','marechal_ferrant',
    'petfriendly','partenaire'
  ) THEN cat_pro
  WHEN cat_pro = 'educateur' OR cat_pro = 'comportementaliste' THEN 'education'
  WHEN cat_pro = 'veto'      OR cat_pro = 'veterinaire'        THEN 'veterinaire'
  WHEN cat_pro = 'garde'                                        THEN 'petsitter'
  ELSE cat_pro
END
WHERE type_profil IS NULL AND cat_pro IS NOT NULL;

-- ─── ÉTAPE 3 : Créer les profils principaux (is_main=TRUE) ──
-- Un profil par utilisateur dans user_profiles, basé sur users

INSERT INTO user_profiles (
  uid,
  type_profil,
  cat_pro,
  is_main,
  nom,
  firstname,
  lastname,
  name_pro,
  phone_number,
  email_contact,
  profile_picture_url,
  profile_picture_url_pro,
  description,
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
  banner_url,
  horaires,
  tarifs,
  durees_motifs,
  created_at
)
SELECT
  u.uid,

  -- type_profil V2
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
    WHEN COALESCE(u.is_pro, FALSE)                                                THEN u.cat_pro
    ELSE 'particulier'
  END,

  -- cat_pro (compatibilité V1)
  COALESCE(u.cat_pro, 'particulier'),

  TRUE,  -- is_main

  -- nom (nom élevage si éleveur, sinon prénom+nom)
  CASE
    WHEN u.name_elevage IS NOT NULL AND u.name_elevage != '' THEN u.name_elevage
    ELSE TRIM(COALESCE(u.firstname,'') || ' ' || COALESCE(u.lastname,''))
  END,

  u.firstname,
  u.lastname,
  u.name_elevage,       -- name_pro
  u.phone_number,
  u.email,              -- email_contact
  u.profile_picture_url,
  u.profile_picture_url_elevage,  -- profile_picture_url_pro
  u.desc_entreprise,    -- description
  u.adress,             -- adresse
  u.rue,
  u.ville,
  u.code_postal,
  NULL,                 -- departement (non stocké sur users en général)
  NULL,                 -- region
  COALESCE(u.pays, 'France'),
  u.lat,
  u.lng,
  u.rue_elevage,        -- rue_pro
  u.ville_elevage,      -- ville_pro
  u.code_postal_elevage,-- code_postal_pro
  u.pays_elevage,       -- pays_pro
  u.instagram,
  u.facebook,
  u.site_web,
  COALESCE(u.is_validate, FALSE),

  -- statut_pro harmonisé V2
  CASE
    WHEN NOT COALESCE(u.is_elevage, FALSE)
     AND NOT COALESCE(u.is_association, FALSE)
     AND NOT COALESCE(u.is_pro, FALSE)                         THEN 'na'
    WHEN COALESCE(u.statut_pro, '') = 'actif'                  THEN 'validated'
    WHEN COALESCE(u.statut_pro, '') = 'en_attente'             THEN 'pending'
    WHEN COALESCE(u.statut_pro, '') = 'refuse'                 THEN 'rejected'
    WHEN COALESCE(u.is_validate, FALSE)                        THEN 'validated'
    ELSE 'pending'
  END,

  u.rejection_reason,
  u.siret,
  u.numero_tva,
  u.kbis_url,
  u.acaced_numero,      -- acaced
  u.acaced_date_obtention,
  u.acaced_doc_url,
  COALESCE(u.certifications, '[]'),
  u.numero_elevage,
  COALESCE(u.especes_elevees, '[]'),
  NULL,                 -- especes_accueil (spécifique association)
  NULL,                 -- capacite_accueil
  CASE
    WHEN u.especes_acceptees IS NOT NULL
    THEN to_jsonb(u.especes_acceptees)
    ELSE NULL
  END,
  u.date_of_birth,
  u.fcm_token,
  u.apns_token,
  COALESCE(u.is_premium, FALSE),
  NULL,                 -- banner_url
  '{}',                 -- horaires
  NULL,                 -- tarifs
  '{}',                 -- durees_motifs
  u.created_at

FROM users u
WHERE NOT EXISTS (
  SELECT 1 FROM user_profiles up
  WHERE up.uid = u.uid AND up.is_main = TRUE
);

-- ─── ÉTAPE 4 : Profil particulier secondaire pour tous les pros ─

INSERT INTO user_profiles (
  uid, type_profil, cat_pro, is_main,
  nom, firstname, lastname,
  phone_number, email_contact,
  profile_picture_url,
  adresse, rue, ville, code_postal, pays, lat, lng,
  instagram, facebook, site_web,
  is_validate, statut_pro,
  date_of_birth,
  fcm_token, apns_token,
  created_at
)
SELECT
  u.uid, 'particulier', 'particulier', FALSE,
  TRIM(COALESCE(u.firstname,'') || ' ' || COALESCE(u.lastname,'')),
  u.firstname, u.lastname,
  u.phone_number, u.email,
  u.profile_picture_url,
  u.adress, u.rue, u.ville, u.code_postal,
  COALESCE(u.pays,'France'), u.lat, u.lng,
  u.instagram, u.facebook, u.site_web,
  TRUE, 'na',
  u.date_of_birth,
  u.fcm_token, u.apns_token,
  u.created_at
FROM users u
WHERE (
  COALESCE(u.is_elevage, FALSE) = TRUE
  OR COALESCE(u.is_association, FALSE) = TRUE
  OR COALESCE(u.is_pro, FALSE) = TRUE
)
AND NOT EXISTS (
  SELECT 1 FROM user_profiles up
  WHERE up.uid = u.uid
    AND up.type_profil = 'particulier'
    AND up.is_main = FALSE
);

-- ─── ÉTAPE 5 : Mise à jour users.profile_id ─────────────────
-- Relier chaque user à son profil principal (UUID)

UPDATE users u
SET profile_id = up.id
FROM user_profiles up
WHERE up.uid = u.uid
  AND up.is_main = TRUE
  AND (u.profile_id IS NULL OR u.profile_id != up.id);

-- ─── ÉTAPE 6 : Index et contraintes FK ──────────────────────

CREATE INDEX IF NOT EXISTS idx_user_profiles_uid
  ON user_profiles (uid);

CREATE INDEX IF NOT EXISTS idx_user_profiles_type
  ON user_profiles (type_profil);

CREATE INDEX IF NOT EXISTS idx_user_profiles_statut
  ON user_profiles (statut_pro) WHERE statut_pro IN ('pending','en_attente');

-- FK users.profile_id → user_profiles.id (si pas déjà présente)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'users'
      AND constraint_name = 'users_profile_id_fkey'
  ) THEN
    ALTER TABLE users
      ADD CONSTRAINT users_profile_id_fkey
      FOREIGN KEY (profile_id) REFERENCES user_profiles(id) ON DELETE SET NULL;
  END IF;
END $$;

-- ─── VÉRIFICATION ────────────────────────────────────────────

SELECT
  type_profil,
  COUNT(*) FILTER (WHERE is_main = TRUE)  AS profils_principaux,
  COUNT(*) FILTER (WHERE is_main = FALSE) AS profils_secondaires
FROM user_profiles
GROUP BY type_profil
ORDER BY type_profil;
