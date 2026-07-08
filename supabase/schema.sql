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
  espece_autre          TEXT,
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
  age_estime            BOOLEAN DEFAULT FALSE,
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
  espece_autre          TEXT,
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
  age_estime            BOOLEAN DEFAULT FALSE,
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

-- ─── MARQUES ALIMENTS ────────────────────────────────────────
-- Table de référence des marques/gammes avec densité et doses

CREATE TABLE marques_aliments (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  marque            TEXT NOT NULL,
  gamme             TEXT NOT NULL,
  espece            TEXT NOT NULL,        -- 'chien', 'chat', 'cheval', 'lapin'…
  taille_race       TEXT,                 -- 'mini', 'medium', 'maxi', 'all'
  age_categorie     TEXT DEFAULT 'adulte', -- 'junior', 'adulte', 'senior'
  type_aliment      TEXT DEFAULT 'croquettes', -- 'croquettes', 'pâtée', 'barf', 'granulés'
  densite_kcal_100g NUMERIC,              -- kcal/100g
  -- Tableau de doses : [{"poids_kg": 10, "grammes": 170}, ...]
  doses             JSONB DEFAULT '[]',
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_marques_espece ON marques_aliments(espece);
CREATE INDEX idx_marques_taille ON marques_aliments(taille_race);

-- ─── SEED — Marques aliments ─────────────────────────────────
-- Sources : royalcanin.com/fr, hillspet.fr, eukanuba.eu, orijen, acana

INSERT INTO marques_aliments (marque, gamme, espece, taille_race, age_categorie, densite_kcal_100g, doses, notes) VALUES

-- ── Royal Canin Chien ──────────────────────────────────────────────────────
('Royal Canin', 'Mini Adult', 'chien', 'mini', 'adulte', 392,
  '[{"poids_kg":2,"grammes":47},{"poids_kg":4,"grammes":79},{"poids_kg":6,"grammes":107},{"poids_kg":8,"grammes":133},{"poids_kg":10,"grammes":158}]',
  'Chiens 1–10 kg, 10 mois à 12 ans. Activité normale.'),

('Royal Canin', 'Medium Adult', 'chien', 'medium', 'adulte', 362,
  '[{"poids_kg":11,"grammes":174},{"poids_kg":14,"grammes":208},{"poids_kg":16,"grammes":230},{"poids_kg":20,"grammes":272},{"poids_kg":25,"grammes":321}]',
  'Chiens 11–25 kg, 1–7 ans. Activité normale.'),

('Royal Canin', 'Maxi Adult', 'chien', 'maxi', 'adulte', 394,
  '[{"poids_kg":26,"grammes":322},{"poids_kg":30,"grammes":359},{"poids_kg":35,"grammes":403},{"poids_kg":40,"grammes":445},{"poids_kg":44,"grammes":478}]',
  'Chiens 26–44 kg, 15 mois à 5 ans. Activité normale.'),

('Royal Canin', 'Mini Adult 8+', 'chien', 'mini', 'senior', 392,
  '[{"poids_kg":2,"grammes":45},{"poids_kg":4,"grammes":75},{"poids_kg":6,"grammes":101},{"poids_kg":8,"grammes":126},{"poids_kg":10,"grammes":149}]',
  'Chiens de moins de 10 kg, dès 8 ans.'),

('Royal Canin', 'Medium Sterilised', 'chien', 'medium', 'adulte', 302,
  '[{"poids_kg":11,"grammes":165},{"poids_kg":14,"grammes":198},{"poids_kg":16,"grammes":217},{"poids_kg":20,"grammes":258},{"poids_kg":25,"grammes":307}]',
  'Chiens stérilisés ou castré 11–25 kg. Densité réduite.'),

-- ── Royal Canin Chat ──────────────────────────────────────────────────────
('Royal Canin', 'Fit 32', 'chat', 'all', 'adulte', 384,
  '[{"poids_kg":2,"grammes":33},{"poids_kg":3,"grammes":44},{"poids_kg":4,"grammes":54},{"poids_kg":5,"grammes":63},{"poids_kg":6,"grammes":71}]',
  'Chat adulte 1–7 ans, accès extérieur. Poids idéal.'),

('Royal Canin', 'Indoor', 'chat', 'all', 'adulte', 334,
  '[{"poids_kg":2,"grammes":36},{"poids_kg":3,"grammes":48},{"poids_kg":4,"grammes":59},{"poids_kg":5,"grammes":70},{"poids_kg":6,"grammes":80}]',
  'Chat adulte d''appartement 1–7 ans.'),

('Royal Canin', 'Sterilised 37', 'chat', 'all', 'adulte', 318,
  '[{"poids_kg":2,"grammes":35},{"poids_kg":3,"grammes":46},{"poids_kg":4,"grammes":57},{"poids_kg":5,"grammes":67},{"poids_kg":6,"grammes":76}]',
  'Chat stérilisé adulte. Réduction pondérale incluse.'),

-- ── Hill''s Science Plan Chien ─────────────────────────────────────────────
('Hill''s', 'Science Plan Adult Medium', 'chien', 'medium', 'adulte', 372,
  '[{"poids_kg":5,"grammes":100},{"poids_kg":10,"grammes":170},{"poids_kg":15,"grammes":230},{"poids_kg":20,"grammes":285},{"poids_kg":25,"grammes":335},{"poids_kg":30,"grammes":385},{"poids_kg":40,"grammes":475}]',
  'Chiens races moyennes adultes. Technologie ActivBiome+.'),

('Hill''s', 'Science Plan Adult Large', 'chien', 'maxi', 'adulte', 365,
  '[{"poids_kg":20,"grammes":270},{"poids_kg":30,"grammes":370},{"poids_kg":40,"grammes":465},{"poids_kg":50,"grammes":555}]',
  'Chiens grandes races adultes.'),

-- ── Hill''s Science Plan Chat ─────────────────────────────────────────────
('Hill''s', 'Science Plan Adult Indoor', 'chat', 'all', 'adulte', 339,
  '[{"poids_kg":2,"grammes":32},{"poids_kg":3,"grammes":43},{"poids_kg":4,"grammes":53},{"poids_kg":5,"grammes":63},{"poids_kg":6,"grammes":72}]',
  'Chat adulte d''appartement.'),

('Hill''s', 'Science Plan Sterilised Cat', 'chat', 'all', 'adulte', 333,
  '[{"poids_kg":2,"grammes":35},{"poids_kg":3,"grammes":46},{"poids_kg":4,"grammes":56},{"poids_kg":5,"grammes":66},{"poids_kg":6,"grammes":75}]',
  'Chat stérilisé adulte.'),

-- ── Purina Pro Plan Chien ─────────────────────────────────────────────────
('Purina', 'Pro Plan Medium Adult OptiBalance', 'chien', 'medium', 'adulte', 367,
  '[{"poids_kg":10,"grammes":162},{"poids_kg":15,"grammes":222},{"poids_kg":20,"grammes":277},{"poids_kg":25,"grammes":329},{"poids_kg":30,"grammes":378}]',
  'Chiens 10–25 kg, formule OptiBalance.'),

('Purina', 'Pro Plan Medium Adult Sensitive Digestion', 'chien', 'medium', 'adulte', 380,
  '[{"poids_kg":10,"grammes":155},{"poids_kg":15,"grammes":213},{"poids_kg":20,"grammes":266},{"poids_kg":25,"grammes":315},{"poids_kg":30,"grammes":362}]',
  'Chiens sensibles digestifs, agneau ou saumon.'),

('Purina', 'Pro Plan Large Adult OptiBalance', 'chien', 'maxi', 'adulte', 367,
  '[{"poids_kg":25,"grammes":329},{"poids_kg":30,"grammes":378},{"poids_kg":35,"grammes":425},{"poids_kg":40,"grammes":470},{"poids_kg":50,"grammes":555}]',
  'Chiens grandes races 25 kg+.'),

-- ── Purina Pro Plan Chat ──────────────────────────────────────────────────
('Purina', 'Pro Plan Adult Sensitive Digestion Chat', 'chat', 'all', 'adulte', 375,
  '[{"poids_kg":2,"grammes":28},{"poids_kg":3,"grammes":38},{"poids_kg":4,"grammes":47},{"poids_kg":5,"grammes":55},{"poids_kg":6,"grammes":63}]',
  'Chat adulte digestion sensible.'),

('Purina', 'Pro Plan Sterilised Optirenal Chat', 'chat', 'all', 'adulte', 360,
  '[{"poids_kg":2,"grammes":30},{"poids_kg":3,"grammes":40},{"poids_kg":4,"grammes":49},{"poids_kg":5,"grammes":58},{"poids_kg":6,"grammes":66}]',
  'Chat stérilisé adulte, protection rénale.'),

-- ── Eukanuba Chien ────────────────────────────────────────────────────────
('Eukanuba', 'Adult Medium Breed', 'chien', 'medium', 'adulte', 355,
  '[{"poids_kg":8,"grammes":115},{"poids_kg":10,"grammes":132},{"poids_kg":15,"grammes":175},{"poids_kg":20,"grammes":210},{"poids_kg":25,"grammes":245}]',
  'Chiens races moyennes adultes.'),

('Eukanuba', 'Adult Large Breed', 'chien', 'maxi', 'adulte', 350,
  '[{"poids_kg":25,"grammes":285},{"poids_kg":30,"grammes":330},{"poids_kg":35,"grammes":370},{"poids_kg":40,"grammes":410},{"poids_kg":50,"grammes":485}]',
  'Chiens grandes races adultes (25–70 kg).'),

-- ── Orijen Chien ──────────────────────────────────────────────────────────
('Orijen', 'Original', 'chien', 'all', 'adulte', 386,
  '[{"poids_kg":5,"grammes":70},{"poids_kg":10,"grammes":117},{"poids_kg":15,"grammes":160},{"poids_kg":20,"grammes":200},{"poids_kg":25,"grammes":238},{"poids_kg":30,"grammes":274},{"poids_kg":40,"grammes":342}]',
  '85% viande, poisson, œufs. Sans céréales.'),

('Orijen', 'Regional Red', 'chien', 'all', 'adulte', 390,
  '[{"poids_kg":5,"grammes":68},{"poids_kg":10,"grammes":115},{"poids_kg":15,"grammes":157},{"poids_kg":20,"grammes":197},{"poids_kg":30,"grammes":270},{"poids_kg":40,"grammes":338}]',
  'Viandes rouges & sanglier. Sans céréales.'),

-- ── Acana Chien ───────────────────────────────────────────────────────────
('Acana', 'Pacifica', 'chien', 'all', 'adulte', 385,
  '[{"poids_kg":5,"grammes":71},{"poids_kg":10,"grammes":119},{"poids_kg":15,"grammes":163},{"poids_kg":20,"grammes":203},{"poids_kg":25,"grammes":241},{"poids_kg":30,"grammes":277}]',
  'Poissons sauvages. Sans céréales.'),

('Acana', 'Singles Duck & Pear', 'chien', 'all', 'adulte', 378,
  '[{"poids_kg":5,"grammes":73},{"poids_kg":10,"grammes":122},{"poids_kg":15,"grammes":167},{"poids_kg":20,"grammes":208},{"poids_kg":30,"grammes":285}]',
  'Monoprotéine canard. Sans céréales. Idéal allergies.'),

-- ── Granulés Cheval ───────────────────────────────────────────────────────
('Sainfoin', 'Granulés Complet Cheval', 'cheval', 'all', 'adulte', 320,
  '[]',
  'Granulés équilibrés, base foin. Activité normale. Dose : 1–3 kg/j selon travail.'),

('Pavo', 'SpeediBeet', 'cheval', 'all', 'adulte', 290,
  '[]',
  'Betterave pressée à tremper. Complément digestif et énergétique. 0.5–1 kg/j.'),

-- ── Granulés Lapin ────────────────────────────────────────────────────────
('Versele-Laga', 'Complete Cunipic Cuni', 'lapin', 'all', 'adulte', 260,
  '[{"poids_kg":1,"grammes":22},{"poids_kg":2,"grammes":45},{"poids_kg":3,"grammes":67},{"poids_kg":4,"grammes":90},{"poids_kg":5,"grammes":112}]',
  'Granulés lapin adulte. 22.5 g/kg/j. Foin illimité obligatoire.'),

-- ── Bab''in Nutrition — Chien ─────────────────────────────────────────────
('Bab''in', 'Mini Adulte Poulet',           'chien', 'mini',   'adulte', 388,
  '[{"poids_kg":2,"grammes":50},{"poids_kg":4,"grammes":83},{"poids_kg":6,"grammes":112},{"poids_kg":8,"grammes":139},{"poids_kg":10,"grammes":163}]',
  'Chiens 1–10 kg. Poulet français. Glucosamine + chondroïtine. Origine France Garantie.'),

('Bab''in', 'Mini Adulte Sans Céréales',    'chien', 'mini',   'adulte', 387,
  '[{"poids_kg":2,"grammes":50},{"poids_kg":4,"grammes":84},{"poids_kg":6,"grammes":113},{"poids_kg":8,"grammes":140},{"poids_kg":10,"grammes":164}]',
  'Chiens 1–10 kg sensibles. Sans céréales.'),

('Bab''in', 'Medium Adulte Poulet',         'chien', 'medium', 'adulte', 388,
  '[{"poids_kg":10,"grammes":163},{"poids_kg":15,"grammes":224},{"poids_kg":20,"grammes":279},{"poids_kg":25,"grammes":330}]',
  'Chiens 11–25 kg. Poulet français. Fabrication Tarn.'),

('Bab''in', 'Medium Stérilisé Poulet',      'chien', 'medium', 'adulte', 358,
  '[{"poids_kg":10,"grammes":165},{"poids_kg":15,"grammes":227},{"poids_kg":20,"grammes":283},{"poids_kg":25,"grammes":335}]',
  'Chiens stérilisés/castrés 11–25 kg. Lipides réduits (12%).'),

('Bab''in', 'Medium Maxi Adulte Digestif',  'chien', 'medium', 'adulte', 380,
  '[{"poids_kg":10,"grammes":166},{"poids_kg":15,"grammes":228},{"poids_kg":20,"grammes":284},{"poids_kg":30,"grammes":385}]',
  'Sensibilité digestive. Prébiotiques renforcés.'),

('Bab''in', 'Maxi Adulte Poulet',           'chien', 'maxi',   'adulte', 388,
  '[{"poids_kg":26,"grammes":320},{"poids_kg":30,"grammes":362},{"poids_kg":35,"grammes":408},{"poids_kg":40,"grammes":451},{"poids_kg":50,"grammes":531}]',
  'Chiens 26 kg+. Poulet français, croquette XL.'),

('Bab''in', 'Adulte Perte de Poids',        'chien', 'all',    'adulte', 331,
  '[{"poids_kg":5,"grammes":89},{"poids_kg":10,"grammes":149},{"poids_kg":15,"grammes":205},{"poids_kg":20,"grammes":256},{"poids_kg":30,"grammes":349}]',
  'Surpoids toutes races. Protéines 34%, fibres 13%. L-Carnitine 400 mg/kg.'),

('Bab''in', 'Adulte Sans Céréales Canard',  'chien', 'all',    'adulte', 387,
  '[{"poids_kg":10,"grammes":163},{"poids_kg":15,"grammes":224},{"poids_kg":20,"grammes":279},{"poids_kg":30,"grammes":380}]',
  'Digestion sensible. Canard sans céréales.'),

-- ── Bab''in Nutrition — Chat ──────────────────────────────────────────────
('Bab''in', 'Chat Adulte Classique Poulet', 'chat', 'all', 'adulte', 386,
  '[{"poids_kg":2,"grammes":34},{"poids_kg":3,"grammes":45},{"poids_kg":4,"grammes":55},{"poids_kg":5,"grammes":64},{"poids_kg":6,"grammes":73}]',
  'Chat adulte 10 mois+. Poulet 70% protéines animales. Taurine 1200 mg/kg.'),

('Bab''in', 'Chat Adulte Saumon',           'chat', 'all', 'adulte', 385,
  '[{"poids_kg":2,"grammes":34},{"poids_kg":3,"grammes":45},{"poids_kg":4,"grammes":55},{"poids_kg":5,"grammes":65}]',
  'Chat adulte. Saumon riche en oméga-3. Origine France Garantie.'),

('Bab''in', 'Chat Adulte Perte de Poids',   'chat', 'all', 'adulte', 316,
  '[{"poids_kg":2,"grammes":40},{"poids_kg":3,"grammes":53},{"poids_kg":4,"grammes":65},{"poids_kg":5,"grammes":76}]',
  'Chat adulte surpoids. Matières grasses réduites.');

-- ── Pâtées humides — Chat ─────────────────────────────────────────────────
INSERT INTO marques_aliments (marque, gamme, espece, taille_race, age_categorie, type_aliment, densite_kcal_100g, doses, notes) VALUES

('Royal Canin', 'Adult Instinctive Sauce (sachet)', 'chat', 'all', 'adulte', 'pâtée', 76,
  '[{"poids_kg":3,"grammes":140},{"poids_kg":4,"grammes":175},{"poids_kg":5,"grammes":205},{"poids_kg":6,"grammes":235}]',
  'Pâtée humide adulte 1–7 ans. Sachets 85g.'),

('Royal Canin', 'Sterilised Adult Sauce (sachet)',  'chat', 'all', 'adulte', 'pâtée', 80,
  '[{"poids_kg":3,"grammes":148},{"poids_kg":4,"grammes":175},{"poids_kg":5,"grammes":201},{"poids_kg":6,"grammes":225}]',
  'Pâtée chat stérilisé adulte. Sachets 85g.'),

('Sheba', 'Classiques Sélection Boucher',           'chat', 'all', 'adulte', 'pâtée', 82,
  '[{"poids_kg":3,"grammes":128},{"poids_kg":4,"grammes":162},{"poids_kg":5,"grammes":193},{"poids_kg":6,"grammes":221}]',
  'Pâtée premium viandes. Barquettes 85g.'),

('Sheba', 'Les Créations en Sauce (sachet)',         'chat', 'all', 'adulte', 'pâtée', 78,
  '[{"poids_kg":3,"grammes":135},{"poids_kg":4,"grammes":169},{"poids_kg":5,"grammes":201},{"poids_kg":6,"grammes":231}]',
  'Sachets sauce premium 85g.'),

('Whiskas', 'Adult 1+ Terrine Volaille',             'chat', 'all', 'adulte', 'pâtée', 82,
  '[{"poids_kg":3,"grammes":128},{"poids_kg":4,"grammes":162},{"poids_kg":5,"grammes":193},{"poids_kg":6,"grammes":221}]',
  'Terrine humide adulte. Boîtes 400g.'),

('Whiskas', 'Sachet Fraîcheur en Sauce',             'chat', 'all', 'adulte', 'pâtée', 75,
  '[{"poids_kg":3,"grammes":140},{"poids_kg":4,"grammes":175},{"poids_kg":5,"grammes":208},{"poids_kg":6,"grammes":240}]',
  'Sachets fraîcheur 100g.'),

('Felix', 'Le Pâté (sachets)',                       'chat', 'all', 'adulte', 'pâtée', 78,
  '[{"poids_kg":3,"grammes":135},{"poids_kg":4,"grammes":170},{"poids_kg":5,"grammes":202},{"poids_kg":6,"grammes":231}]',
  'Sachets 85g bœuf, volaille, saumon.'),

('Felix', 'Tendres Effilochés en Gelée',             'chat', 'all', 'adulte', 'pâtée', 68,
  '[{"poids_kg":3,"grammes":155},{"poids_kg":4,"grammes":194},{"poids_kg":5,"grammes":231},{"poids_kg":6,"grammes":265}]',
  'Effilochés en gelée 85g. Densité faible, très hydratant.'),

('Hill''s', 'Science Plan Adult Wet Poulet',         'chat', 'all', 'adulte', 'pâtée', 90,
  '[{"poids_kg":3,"grammes":120},{"poids_kg":4,"grammes":150},{"poids_kg":5,"grammes":178},{"poids_kg":6,"grammes":204}]',
  'Pâtée adulte boîtes 156g. ActivBiome+.'),

('Purina', 'Pro Plan Wet Adult Sensitive Saumon',    'chat', 'all', 'adulte', 'pâtée', 95,
  '[{"poids_kg":3,"grammes":114},{"poids_kg":4,"grammes":142},{"poids_kg":5,"grammes":169},{"poids_kg":6,"grammes":193}]',
  'Pâtée chat sensible saumon. Sachets 85g.'),

('Bab''in', 'Chat Terrine Poulet (pâtée)',           'chat', 'all', 'adulte', 'pâtée', 84,
  '[{"poids_kg":3,"grammes":125},{"poids_kg":4,"grammes":157},{"poids_kg":5,"grammes":187},{"poids_kg":6,"grammes":214}]',
  'Terrine humide chat adulte. Fabrication française.'),

-- ── Pâtées humides — Chien ────────────────────────────────────────────────
('Royal Canin', 'Medium Adult Sauce (sachet)',        'chien', 'medium', 'adulte', 'pâtée', 88,
  '[{"poids_kg":11,"grammes":610},{"poids_kg":14,"grammes":730},{"poids_kg":20,"grammes":960},{"poids_kg":25,"grammes":1130}]',
  'Pâtée humide races moyennes. Sachets 140g.'),

('Purina', 'Pro Plan Wet Adult Medium Poulet',        'chien', 'medium', 'adulte', 'pâtée', 100,
  '[{"poids_kg":10,"grammes":630},{"poids_kg":15,"grammes":865},{"poids_kg":20,"grammes":1080},{"poids_kg":25,"grammes":1280}]',
  'Pâtée chien adulte races moyennes. Barquettes 150g.');

