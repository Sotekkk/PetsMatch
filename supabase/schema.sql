-- ============================================================
-- PetsMatch — Schéma PostgreSQL / Supabase
-- Migration depuis Firestore (Firebase Auth conservé)
-- uid = Firebase Auth UID (clé étrangère partout)
-- ============================================================

-- ─── USERS ──────────────────────────────────────────────────

CREATE TABLE users (
  uid                         TEXT PRIMARY KEY,
  -- Particulier
  firstname                   TEXT,
  lastname                    TEXT,
  email                       TEXT,
  date_of_birth               DATE,
  phone_number                TEXT,
  code_iso                    TEXT,
  adress                      TEXT,
  rue                         TEXT,
  ville                       TEXT,
  code_postal                 TEXT,
  pays                        TEXT,
  profile_picture_url         TEXT,
  bio                         TEXT,
  -- Éleveur
  is_elevage                  BOOLEAN DEFAULT FALSE,
  is_validate                 BOOLEAN DEFAULT FALSE,
  name_elevage                TEXT,
  adress_elevage              TEXT,
  rue_elevage                 TEXT,
  ville_elevage               TEXT,
  code_postal_elevage         TEXT,
  pays_elevage                TEXT,
  departement_elevage         TEXT,
  region_elevage              TEXT,
  code_iso_elevage            TEXT,
  numero_elevage              TEXT,
  profile_picture_url_elevage TEXT,
  desc_entreprise             TEXT,
  document_elevage            TEXT,
  validate_account_elevage    BOOLEAN DEFAULT FALSE,
  rejection_reason            TEXT,
  verification_status         TEXT,
  kbis_url                    TEXT,
  -- Espèces élevées (nouveau format)
  especes_elevees             JSONB DEFAULT '[]',
  -- Ancien format (compatibilité)
  is_dog                      BOOLEAN DEFAULT FALSE,
  is_cat                      BOOLEAN DEFAULT FALSE,
  dog_breeds                  JSONB DEFAULT '[]',
  cat_breeds                  JSONB DEFAULT '[]',
  -- Pro
  is_pub                      BOOLEAN DEFAULT FALSE,
  is_pro                      BOOLEAN DEFAULT FALSE,
  cat_pro                     TEXT,
  siret                       TEXT,
  numero_tva                  TEXT,
  profession_pro              TEXT,
  is_partenaire               BOOLEAN DEFAULT FALSE,
  -- Certifications
  acaced_numero               TEXT,
  acaced_date_obtention       DATE,
  acaced_doc_url              TEXT,
  -- Admin
  is_admin                    BOOLEAN DEFAULT FALSE,
  is_dev                      BOOLEAN DEFAULT FALSE,
  -- Géolocalisation
  lat                         DOUBLE PRECISION,
  lng                         DOUBLE PRECISION,
  -- Abonnement
  valid_until                 TIMESTAMPTZ,
  reminder_15_sent            BOOLEAN DEFAULT FALSE,
  reminder_21_sent            BOOLEAN DEFAULT FALSE,
  -- Notifications
  fcm_token                   TEXT,
  apns_token                  TEXT,
  -- Présence
  is_online                   BOOLEAN DEFAULT FALSE,
  last_active                 TIMESTAMPTZ,
  -- Timestamps
  created_at                  TIMESTAMPTZ DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ DEFAULT NOW()
);

-- ─── ANIMAUX ────────────────────────────────────────────────

CREATE TABLE animaux (
  id                    TEXT PRIMARY KEY,
  uid_eleveur           TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  nom                   TEXT,
  espece                TEXT,
  race                  TEXT,
  sexe                  TEXT,
  statut                TEXT DEFAULT 'present',
  photo_url             TEXT,
  couleur               TEXT,
  identification        TEXT,
  taille                TEXT,
  poids                 TEXT,
  notes                 TEXT,
  description           TEXT,
  date_naissance        DATE,
  sterilise             BOOLEAN DEFAULT FALSE,
  type_poil             TEXT,
  -- Pedigree / registre
  pedigree              BOOLEAN DEFAULT FALSE,
  club_registre         TEXT,
  pedigree_lof          TEXT,
  pedigree_url          TEXT,
  passeport_europeen    TEXT,
  -- Généalogie
  nom_pere              TEXT,
  puce_pere             TEXT,
  nom_mere              TEXT,
  puce_mere             TEXT,
  race_mere             TEXT,
  date_naissance_mere   DATE,
  -- Entrée / Sortie
  date_entree           DATE,
  date_sortie           DATE,
  provenance_nom        TEXT,
  provenance_qualite    TEXT,
  provenance_adresse    TEXT,
  importation_ref       TEXT,
  destinataire_nom      TEXT,
  destinataire_qualite  TEXT,
  destinataire_adresse  TEXT,
  cause_mort            TEXT,
  -- Divers
  documents             JSONB DEFAULT '[]',
  contacts_urgence      JSONB DEFAULT '[]',
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);

-- ─── ANNONCES ───────────────────────────────────────────────

CREATE TABLE annonces (
  id                    TEXT PRIMARY KEY,
  uid_eleveur           TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  nom_eleveur           TEXT,
  ville_eleveur         TEXT,
  departement_eleveur   TEXT,
  region_eleveur        TEXT,
  pays_eleveur          TEXT,
  -- Annonce
  type                  TEXT,
  type_vente            TEXT,
  espece                TEXT,
  race                  TEXT,
  titre                 TEXT,
  description           TEXT,
  photos                JSONB DEFAULT '[]',
  prix                  NUMERIC(10,2),
  prix_negociable       BOOLEAN DEFAULT FALSE,
  statut                TEXT DEFAULT 'disponible',
  -- Animal
  date_naissance        DATE,
  date_naissance_animal DATE,
  sexe                  TEXT,
  couleur               TEXT,
  sterilise             BOOLEAN DEFAULT FALSE,
  semaines              INTEGER,
  -- Portée
  nombre_bebes          INTEGER,
  animaux_portee        JSONB DEFAULT '[]',
  prix_min_portee       NUMERIC(10,2),
  prix_max_portee       NUMERIC(10,2),
  -- Parents
  mere_animal_id        TEXT,
  mere_photo_url        TEXT,
  mere_nom              TEXT,
  mere_puce             TEXT,
  mere_registre         TEXT,
  pere_animal_id        TEXT,
  pere_photo_url        TEXT,
  pere_nom              TEXT,
  pere_puce             TEXT,
  pere_registre         TEXT,
  -- Registre
  registre_type         TEXT,
  numero_registre       TEXT,
  club_pedigree         TEXT,
  studbook              TEXT,
  -- Santé
  vaccines              BOOLEAN DEFAULT FALSE,
  vermifuge             BOOLEAN DEFAULT FALSE,
  identification        BOOLEAN DEFAULT FALSE,
  bilan_sante           BOOLEAN DEFAULT FALSE,
  -- Saillie
  etalon_animal_id      TEXT,
  saillie_prix          NUMERIC(10,2),
  saillie_conditions    TEXT,
  -- Stats
  vues                  INTEGER DEFAULT 0,
  contacts              INTEGER DEFAULT 0,
  -- Géolocalisation
  lat                   DOUBLE PRECISION,
  lng                   DOUBLE PRECISION,
  -- Timestamps
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW(),
  expires_at            TIMESTAMPTZ
);

-- ─── CONVERSATIONS ──────────────────────────────────────────

CREATE TABLE conversations (
  id              TEXT PRIMARY KEY,
  participant_ids TEXT NOT NULL,
  participants    JSONB DEFAULT '[]',
  last_message    TEXT,
  unread_count    JSONB DEFAULT '{}',
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE messages (
  id              TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id       TEXT NOT NULL,
  text            TEXT,
  image_url       TEXT,
  is_read         BOOLEAN DEFAULT FALSE,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ─── POSTS ──────────────────────────────────────────────────

CREATE TABLE posts (
  id              TEXT PRIMARY KEY,
  uid_eleveur     TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  contenu         TEXT,
  title           TEXT,
  media_stockage  JSONB DEFAULT '[]',
  tags            JSONB DEFAULT '[]',
  is_photo        BOOLEAN DEFAULT TRUE,
  is_boost        BOOLEAN DEFAULT FALSE,
  is_urgent       BOOLEAN DEFAULT FALSE,
  is_cat          BOOLEAN DEFAULT FALSE,
  is_dog          BOOLEAN DEFAULT FALSE,
  is_sell         BOOLEAN DEFAULT FALSE,
  is_sailli       BOOLEAN DEFAULT FALSE,
  is_retraite     BOOLEAN DEFAULT FALSE,
  is_loof         BOOLEAN DEFAULT FALSE,
  is_lof          BOOLEAN DEFAULT FALSE,
  is_vaccined     BOOLEAN DEFAULT FALSE,
  is_male         BOOLEAN DEFAULT FALSE,
  is_pro          BOOLEAN DEFAULT FALSE,
  is_adult        BOOLEAN DEFAULT FALSE,
  more_eight_weeks BOOLEAN DEFAULT FALSE,
  date_of_birth   DATE,
  puce_number     TEXT,
  number_porter   INTEGER,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE liked_posts (
  user_id   TEXT NOT NULL,
  post_id   TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, post_id)
);

CREATE TABLE bloquer (
  blocker_id  TEXT NOT NULL,
  blocked_id  TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (blocker_id, blocked_id)
);

-- ─── SANTÉ ANIMAUX (sous-collections) ───────────────────────

CREATE TABLE vaccinations (
  id          TEXT PRIMARY KEY,
  animal_id   TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  vaccin      TEXT,
  lot         TEXT,
  veterinaire TEXT,
  date        DATE,
  date_rappel DATE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE traitements (
  id          TEXT PRIMARY KEY,
  animal_id   TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  type        TEXT,
  nom         TEXT,
  posologie   TEXT,
  date        DATE,
  date_fin    DATE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE visites (
  id          TEXT PRIMARY KEY,
  animal_id   TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  motif       TEXT,
  veterinaire TEXT,
  date        DATE,
  diagnostic  TEXT,
  notes       TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE vermifuges (
  id          TEXT PRIMARY KEY,
  animal_id   TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  produit     TEXT,
  dosage      TEXT,
  date        DATE,
  date_rappel DATE,
  notes       TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE antiparasitaires (
  id          TEXT PRIMARY KEY,
  animal_id   TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  produit     TEXT,
  type        TEXT,
  date        DATE,
  date_rappel DATE,
  frequence   TEXT,
  notes       TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE allergies (
  id          TEXT PRIMARY KEY,
  animal_id   TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  description TEXT,
  type        TEXT,
  severite    TEXT,
  notes       TEXT,
  date        DATE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE poids (
  id          TEXT PRIMARY KEY,
  animal_id   TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  valeur      NUMERIC(6,3),
  date        DATE,
  notes       TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE chaleurs (
  id          TEXT PRIMARY KEY,
  animal_id   TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  date        DATE,
  duree       TEXT,
  notes       TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE saillies (
  id               TEXT PRIMARY KEY,
  animal_id        TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  male_name        TEXT,
  male_id          TEXT,
  nom_partenaire   TEXT,
  ident_partenaire TEXT,
  methode          TEXT,
  date             DATE,
  notes            TEXT,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE gestations (
  id                TEXT PRIMARY KEY,
  animal_id         TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  date              DATE,
  date_prevue       DATE,
  date_naissance    DATE,
  date_accouchement DATE,
  nombre_bebes      INTEGER,
  nb_attendu        INTEGER,
  nb_nes            INTEGER,
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

-- ─── ÉLEVEUR (sous-collections) ─────────────────────────────

CREATE TABLE registre_sanitaire (
  id              TEXT PRIMARY KEY,
  uid_eleveur     TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  animal_nom      TEXT,
  espece          TEXT,
  date_naissance  DATE,
  identification  TEXT,
  sexe            TEXT,
  type_acte       TEXT,
  date_acte       DATE,
  intervenant     TEXT,
  description     TEXT,
  ordonnance_num  TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE factures (
  id                    TEXT PRIMARY KEY,
  uid_eleveur           TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  numero_facture        TEXT,
  date_facture          DATE,
  date_prestation       DATE,
  date_echeance         DATE,
  lignes                JSONB DEFAULT '[]',
  total_ht              NUMERIC(10,2),
  total_tva             NUMERIC(10,2),
  total_ttc             NUMERIC(10,2),
  regime_tva            TEXT,
  nom_client            TEXT,
  prenom_client         TEXT,
  email_client          TEXT,
  telephone_client      TEXT,
  rue_client            TEXT,
  cp_client             TEXT,
  ville_client          TEXT,
  pays_client           TEXT,
  nom_emetteur          TEXT,
  rue_emetteur          TEXT,
  cp_emetteur           TEXT,
  ville_emetteur        TEXT,
  pays_emetteur         TEXT,
  siret_emetteur        TEXT,
  tva_emetteur          TEXT,
  email_emetteur        TEXT,
  mode_paiement         TEXT,
  delai_paiement        TEXT,
  note_complementaire   TEXT,
  statut                TEXT DEFAULT 'brouillon',
  created_at            TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE contrats (
  id            TEXT PRIMARY KEY,
  uid_eleveur   TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  nom           TEXT,
  type          TEXT,
  storage_path  TEXT,
  url           TEXT,
  ext           TEXT,
  statut        TEXT,
  date_upload   TIMESTAMPTZ DEFAULT NOW(),
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE subscriptions (
  id          TEXT PRIMARY KEY,
  uid         TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  plan_type   TEXT,
  status      TEXT,
  start_date  TIMESTAMPTZ,
  end_date    TIMESTAMPTZ,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ─── INDEX (performances) ────────────────────────────────────

CREATE INDEX idx_animaux_uid_eleveur    ON animaux(uid_eleveur);
CREATE INDEX idx_annonces_uid_eleveur   ON annonces(uid_eleveur);
CREATE INDEX idx_annonces_espece        ON annonces(espece);
CREATE INDEX idx_annonces_statut        ON annonces(statut);
CREATE INDEX idx_annonces_region        ON annonces(region_eleveur);
CREATE INDEX idx_annonces_departement   ON annonces(departement_eleveur);
CREATE INDEX idx_messages_conversation  ON messages(conversation_id);
CREATE INDEX idx_posts_uid_eleveur      ON posts(uid_eleveur);
CREATE INDEX idx_users_is_elevage       ON users(is_elevage);
CREATE INDEX idx_users_is_validate      ON users(is_validate);
CREATE INDEX idx_vaccinations_animal    ON vaccinations(animal_id);
CREATE INDEX idx_traitements_animal     ON traitements(animal_id);
CREATE INDEX idx_visites_animal         ON visites(animal_id);
