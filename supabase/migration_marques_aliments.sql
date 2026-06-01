-- Migration : création et seed de la table marques_aliments
-- À exécuter dans l'éditeur SQL Supabase

-- ── Suppression + recréation propre ──────────────────────────
DROP TABLE IF EXISTS marques_aliments CASCADE;

CREATE TABLE marques_aliments (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  marque            TEXT NOT NULL,
  gamme             TEXT NOT NULL,
  espece            TEXT NOT NULL,
  taille_race       TEXT,
  age_categorie     TEXT DEFAULT 'adulte',
  type_aliment      TEXT DEFAULT 'croquettes',
  densite_kcal_100g NUMERIC,
  doses             JSONB DEFAULT '[]',
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_marques_espece ON marques_aliments(espece);
CREATE INDEX idx_marques_taille ON marques_aliments(taille_race);

-- Row Level Security (lecture publique, écriture admin seulement)
ALTER TABLE marques_aliments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Marques lisibles par tous" ON marques_aliments;
CREATE POLICY "Marques lisibles par tous" ON marques_aliments FOR SELECT USING (true);

-- ── Seed ─────────────────────────────────────────────────────
-- Sources : royalcanin.com/fr, hillspet.fr, eukanuba.eu, orijen, acana
-- Doses = activité normale / poids idéal

INSERT INTO marques_aliments (marque, gamme, espece, taille_race, age_categorie, densite_kcal_100g, doses, notes) VALUES

-- ────────────────── CHIEN ──────────────────────────────────────

-- Royal Canin
('Royal Canin', 'Mini Adult',            'chien', 'mini',   'adulte', 392,
 '[{"poids_kg":2,"grammes":47},{"poids_kg":4,"grammes":79},{"poids_kg":6,"grammes":107},{"poids_kg":8,"grammes":133},{"poids_kg":10,"grammes":158}]',
 'Chiens 1–10 kg, 10 mois à 12 ans. Activité normale.'),

('Royal Canin', 'Mini Adult 8+',         'chien', 'mini',   'senior', 392,
 '[{"poids_kg":2,"grammes":45},{"poids_kg":4,"grammes":75},{"poids_kg":6,"grammes":101},{"poids_kg":8,"grammes":126},{"poids_kg":10,"grammes":149}]',
 'Chiens de moins de 10 kg, dès 8 ans.'),

('Royal Canin', 'Medium Adult',          'chien', 'medium', 'adulte', 362,
 '[{"poids_kg":11,"grammes":174},{"poids_kg":14,"grammes":208},{"poids_kg":16,"grammes":230},{"poids_kg":20,"grammes":272},{"poids_kg":25,"grammes":321}]',
 'Chiens 11–25 kg, 1–7 ans. Activité normale.'),

('Royal Canin', 'Medium Sterilised',     'chien', 'medium', 'adulte', 302,
 '[{"poids_kg":11,"grammes":165},{"poids_kg":14,"grammes":198},{"poids_kg":16,"grammes":217},{"poids_kg":20,"grammes":258},{"poids_kg":25,"grammes":307}]',
 'Chiens stérilisés/castrés 11–25 kg.'),

('Royal Canin', 'Maxi Adult',            'chien', 'maxi',   'adulte', 394,
 '[{"poids_kg":26,"grammes":322},{"poids_kg":30,"grammes":359},{"poids_kg":35,"grammes":403},{"poids_kg":40,"grammes":445},{"poids_kg":44,"grammes":478}]',
 'Chiens 26–44 kg, 15 mois à 5 ans. Activité normale.'),

('Royal Canin', 'Maxi Adult 5+',         'chien', 'maxi',   'senior', 370,
 '[{"poids_kg":26,"grammes":320},{"poids_kg":30,"grammes":356},{"poids_kg":35,"grammes":400},{"poids_kg":40,"grammes":440},{"poids_kg":44,"grammes":472}]',
 'Chiens grandes races, dès 5 ans.'),

-- Hill''s Science Plan
('Hill''s', 'Science Plan Adult Medium', 'chien', 'medium', 'adulte', 372,
 '[{"poids_kg":5,"grammes":100},{"poids_kg":10,"grammes":170},{"poids_kg":15,"grammes":230},{"poids_kg":20,"grammes":285},{"poids_kg":25,"grammes":335},{"poids_kg":30,"grammes":385},{"poids_kg":40,"grammes":475}]',
 'Chiens races moyennes adultes. ActivBiome+.'),

('Hill''s', 'Science Plan Adult Large',  'chien', 'maxi',   'adulte', 365,
 '[{"poids_kg":20,"grammes":270},{"poids_kg":30,"grammes":370},{"poids_kg":40,"grammes":465},{"poids_kg":50,"grammes":555}]',
 'Chiens grandes races adultes.'),

('Hill''s', 'Science Plan Sterilised Medium', 'chien', 'medium', 'adulte', 330,
 '[{"poids_kg":10,"grammes":170},{"poids_kg":15,"grammes":225},{"poids_kg":20,"grammes":278},{"poids_kg":25,"grammes":328}]',
 'Chiens stérilisés/castrés races moyennes.'),

-- Purina Pro Plan
('Purina', 'Pro Plan Medium Adult OptiBalance',          'chien', 'medium', 'adulte', 367,
 '[{"poids_kg":10,"grammes":162},{"poids_kg":15,"grammes":222},{"poids_kg":20,"grammes":277},{"poids_kg":25,"grammes":329},{"poids_kg":30,"grammes":378}]',
 'Chiens 10–25 kg, formule OptiBalance.'),

('Purina', 'Pro Plan Medium Adult Sensitive Digestion',  'chien', 'medium', 'adulte', 380,
 '[{"poids_kg":10,"grammes":155},{"poids_kg":15,"grammes":213},{"poids_kg":20,"grammes":266},{"poids_kg":25,"grammes":315},{"poids_kg":30,"grammes":362}]',
 'Chiens digestion sensible, agneau ou saumon.'),

('Purina', 'Pro Plan Large Adult OptiBalance',           'chien', 'maxi',   'adulte', 367,
 '[{"poids_kg":25,"grammes":329},{"poids_kg":30,"grammes":378},{"poids_kg":35,"grammes":425},{"poids_kg":40,"grammes":470},{"poids_kg":50,"grammes":555}]',
 'Chiens grandes races 25 kg+.'),

('Purina', 'Pro Plan Medium Adult Sterilised',           'chien', 'medium', 'adulte', 358,
 '[{"poids_kg":10,"grammes":157},{"poids_kg":15,"grammes":215},{"poids_kg":20,"grammes":268},{"poids_kg":25,"grammes":318}]',
 'Chiens stérilisés races moyennes.'),

-- Eukanuba
('Eukanuba', 'Adult Medium Breed', 'chien', 'medium', 'adulte', 355,
 '[{"poids_kg":8,"grammes":115},{"poids_kg":10,"grammes":132},{"poids_kg":15,"grammes":175},{"poids_kg":20,"grammes":210},{"poids_kg":25,"grammes":245}]',
 'Chiens races moyennes adultes.'),

('Eukanuba', 'Adult Large Breed',  'chien', 'maxi',   'adulte', 350,
 '[{"poids_kg":25,"grammes":285},{"poids_kg":30,"grammes":330},{"poids_kg":35,"grammes":370},{"poids_kg":40,"grammes":410},{"poids_kg":50,"grammes":485}]',
 'Chiens grandes races adultes.'),

-- Orijen
('Orijen', 'Original',      'chien', 'all', 'adulte', 386,
 '[{"poids_kg":5,"grammes":70},{"poids_kg":10,"grammes":117},{"poids_kg":15,"grammes":160},{"poids_kg":20,"grammes":200},{"poids_kg":25,"grammes":238},{"poids_kg":30,"grammes":274},{"poids_kg":40,"grammes":342}]',
 '85% viande, poisson, œufs. Sans céréales.'),

('Orijen', 'Regional Red',  'chien', 'all', 'adulte', 390,
 '[{"poids_kg":5,"grammes":68},{"poids_kg":10,"grammes":115},{"poids_kg":15,"grammes":157},{"poids_kg":20,"grammes":197},{"poids_kg":30,"grammes":270},{"poids_kg":40,"grammes":338}]',
 'Viandes rouges et sanglier. Sans céréales.'),

('Orijen', 'Six Fish',      'chien', 'all', 'adulte', 388,
 '[{"poids_kg":5,"grammes":69},{"poids_kg":10,"grammes":116},{"poids_kg":15,"grammes":159},{"poids_kg":20,"grammes":199},{"poids_kg":30,"grammes":272}]',
 '6 poissons sauvages. Sans céréales.'),

-- Acana
('Acana', 'Pacifica',                    'chien', 'all', 'adulte', 385,
 '[{"poids_kg":5,"grammes":71},{"poids_kg":10,"grammes":119},{"poids_kg":15,"grammes":163},{"poids_kg":20,"grammes":203},{"poids_kg":25,"grammes":241},{"poids_kg":30,"grammes":277}]',
 'Poissons sauvages. Sans céréales.'),

('Acana', 'Singles Duck & Pear',         'chien', 'all', 'adulte', 378,
 '[{"poids_kg":5,"grammes":73},{"poids_kg":10,"grammes":122},{"poids_kg":15,"grammes":167},{"poids_kg":20,"grammes":208},{"poids_kg":30,"grammes":285}]',
 'Monoprotéine canard. Idéal allergies. Sans céréales.'),

('Acana', 'Grasslands',                  'chien', 'all', 'adulte', 380,
 '[{"poids_kg":5,"grammes":72},{"poids_kg":10,"grammes":121},{"poids_kg":15,"grammes":166},{"poids_kg":20,"grammes":207},{"poids_kg":30,"grammes":283}]',
 'Agneau & canard de pâture. Sans céréales.'),

-- ────────────────── CHAT ───────────────────────────────────────

-- Royal Canin Chat
('Royal Canin', 'Fit 32',          'chat', 'all', 'adulte', 384,
 '[{"poids_kg":2,"grammes":33},{"poids_kg":3,"grammes":44},{"poids_kg":4,"grammes":54},{"poids_kg":5,"grammes":63},{"poids_kg":6,"grammes":71}]',
 'Chat adulte 1–7 ans, accès extérieur. Poids idéal.'),

('Royal Canin', 'Indoor',          'chat', 'all', 'adulte', 334,
 '[{"poids_kg":2,"grammes":36},{"poids_kg":3,"grammes":48},{"poids_kg":4,"grammes":59},{"poids_kg":5,"grammes":70},{"poids_kg":6,"grammes":80}]',
 'Chat adulte d''appartement 1–7 ans.'),

('Royal Canin', 'Sterilised 37',   'chat', 'all', 'adulte', 318,
 '[{"poids_kg":2,"grammes":35},{"poids_kg":3,"grammes":46},{"poids_kg":4,"grammes":57},{"poids_kg":5,"grammes":67},{"poids_kg":6,"grammes":76}]',
 'Chat stérilisé adulte.'),

('Royal Canin', 'Persian Adult',   'chat', 'all', 'adulte', 362,
 '[{"poids_kg":2,"grammes":34},{"poids_kg":3,"grammes":45},{"poids_kg":4,"grammes":55},{"poids_kg":5,"grammes":64}]',
 'Chat Persan adulte. Croquette à mâcher adaptée à la morphologie brachycéphale.'),

('Royal Canin', 'Maine Coon Adult','chat', 'all', 'adulte', 367,
 '[{"poids_kg":4,"grammes":56},{"poids_kg":6,"grammes":76},{"poids_kg":8,"grammes":94},{"poids_kg":10,"grammes":112}]',
 'Chat Maine Coon adulte ≥ 15 mois.'),

('Royal Canin', 'Siamese Adult',   'chat', 'all', 'adulte', 341,
 '[{"poids_kg":2,"grammes":38},{"poids_kg":3,"grammes":50},{"poids_kg":4,"grammes":61},{"poids_kg":5,"grammes":72}]',
 'Chat Siamois adulte.'),

-- Hill''s Science Plan Chat
('Hill''s', 'Science Plan Adult Indoor',   'chat', 'all', 'adulte', 339,
 '[{"poids_kg":2,"grammes":32},{"poids_kg":3,"grammes":43},{"poids_kg":4,"grammes":53},{"poids_kg":5,"grammes":63},{"poids_kg":6,"grammes":72}]',
 'Chat adulte d''appartement.'),

('Hill''s', 'Science Plan Sterilised Cat', 'chat', 'all', 'adulte', 333,
 '[{"poids_kg":2,"grammes":35},{"poids_kg":3,"grammes":46},{"poids_kg":4,"grammes":56},{"poids_kg":5,"grammes":66},{"poids_kg":6,"grammes":75}]',
 'Chat stérilisé adulte.'),

-- Purina Pro Plan Chat
('Purina', 'Pro Plan Adult Sensitive Digestion Chat', 'chat', 'all', 'adulte', 375,
 '[{"poids_kg":2,"grammes":28},{"poids_kg":3,"grammes":38},{"poids_kg":4,"grammes":47},{"poids_kg":5,"grammes":55},{"poids_kg":6,"grammes":63}]',
 'Chat adulte digestion sensible.'),

('Purina', 'Pro Plan Sterilised Optirenal Chat',      'chat', 'all', 'adulte', 360,
 '[{"poids_kg":2,"grammes":30},{"poids_kg":3,"grammes":40},{"poids_kg":4,"grammes":49},{"poids_kg":5,"grammes":58},{"poids_kg":6,"grammes":66}]',
 'Chat stérilisé adulte, soutien rénal.'),

-- ────────────────── CHEVAL ─────────────────────────────────────

('Sainfoin',    'Granulés Complet Entretien', 'cheval', 'all', 'adulte', 320,
 '[]',
 'Granulés équilibrés, activité légère à modérée. Dose indicative : 1–3 kg/j.'),

('Pavo',        'EasyFit',                   'cheval', 'all', 'adulte', 310,
 '[]',
 'Céréales partiellement soufflées. Digestion améliorée. 2–4 kg/j selon travail.'),

('Pavo', 'SpeediBeet',                        'cheval', 'all', 'adulte', 290,
 '[]',
 'Betterave pressée à tremper. Complément digestif/énergétique. 0.5–1 kg/j.'),

('LMF Equine',  'Competition',               'cheval', 'all', 'adulte', 345,
 '[]',
 'Aliment haute énergie pour cheval de sport. 3–6 kg/j selon effort.'),

-- ────────────────── LAPIN ──────────────────────────────────────

('Versele-Laga', 'Complete Cunipic Cuni', 'lapin', 'all', 'adulte', 260,
 '[{"poids_kg":1,"grammes":22},{"poids_kg":2,"grammes":45},{"poids_kg":3,"grammes":67},{"poids_kg":4,"grammes":90},{"poids_kg":5,"grammes":112}]',
 'Granulés lapin adulte. 22.5 g/kg/j. Foin illimité obligatoire.'),

('Cunipic', 'Alpha Pro Adult Rabbit', 'lapin', 'all', 'adulte', 250,
 '[{"poids_kg":1,"grammes":23},{"poids_kg":2,"grammes":46},{"poids_kg":3,"grammes":69},{"poids_kg":4,"grammes":92},{"poids_kg":5,"grammes":115}]',
 'Granulés mono-composants. Riche en fibres. Foin illimité.'),

-- ────────────────── OISEAU ─────────────────────────────────────

('Versele-Laga', 'NutriBird P15 Original', 'oiseau', 'all', 'adulte', 380,
 '[]',
 'Granulés perruches et perroquets. 15% protéines. 40–60 g/j perroquet moyen.'),

('Versele-Laga', 'Prestige Perroquet',     'oiseau', 'all', 'adulte', 350,
 '[]',
 'Mélange graines premium. 50–70 g/j perroquet moyen. Compléter avec fruits frais.'),

-- ────────────────── BAB''IN NUTRITION — CHIEN ──────────────────
-- Source : babin-nutrition.com — Marque française, Origine France Garantie

('Bab''in', 'Mini Adulte Poulet',         'chien', 'mini',   'adulte', 388,
 '[{"poids_kg":2,"grammes":50},{"poids_kg":4,"grammes":83},{"poids_kg":6,"grammes":112},{"poids_kg":8,"grammes":139},{"poids_kg":10,"grammes":163}]',
 'Chiens 1–10 kg, 10 mois à 8 ans. Poulet français. Glucosamine + chondroïtine.'),

('Bab''in', 'Mini Adulte Sans Céréales',  'chien', 'mini',   'adulte', 387,
 '[{"poids_kg":2,"grammes":50},{"poids_kg":4,"grammes":84},{"poids_kg":6,"grammes":113},{"poids_kg":8,"grammes":140},{"poids_kg":10,"grammes":164}]',
 'Chiens 1–10 kg sensibles. Sans céréales. Canard ou poulet.'),

('Bab''in', 'Medium Adulte Poulet',       'chien', 'medium', 'adulte', 388,
 '[{"poids_kg":10,"grammes":163},{"poids_kg":15,"grammes":224},{"poids_kg":20,"grammes":279},{"poids_kg":25,"grammes":330}]',
 'Chiens 11–25 kg, 12 mois à 7 ans. Poulet français. Fabrication Tarn.'),

('Bab''in', 'Medium Stérilisé Poulet',    'chien', 'medium', 'adulte', 358,
 '[{"poids_kg":10,"grammes":165},{"poids_kg":15,"grammes":227},{"poids_kg":20,"grammes":283},{"poids_kg":25,"grammes":335}]',
 'Chiens stérilisés/castrés 11–25 kg. Matières grasses réduites (12%).'),

('Bab''in', 'Medium Maxi Adulte Digestif','chien', 'medium', 'adulte', 380,
 '[{"poids_kg":10,"grammes":166},{"poids_kg":15,"grammes":228},{"poids_kg":20,"grammes":284},{"poids_kg":30,"grammes":385}]',
 'Sensibilité digestive, races moyennes et grandes. Prébiotiques renforcés.'),

('Bab''in', 'Maxi Adulte Poulet',         'chien', 'maxi',   'adulte', 388,
 '[{"poids_kg":26,"grammes":320},{"poids_kg":30,"grammes":362},{"poids_kg":35,"grammes":408},{"poids_kg":40,"grammes":451},{"poids_kg":50,"grammes":531}]',
 'Chiens 26 kg+, 15 mois à 6 ans. Poulet français, croquette XL.'),

('Bab''in', 'Adulte Perte de Poids',      'chien', 'all',    'adulte', 331,
 '[{"poids_kg":5,"grammes":89},{"poids_kg":10,"grammes":149},{"poids_kg":15,"grammes":205},{"poids_kg":20,"grammes":256},{"poids_kg":30,"grammes":349}]',
 'Surpoids toutes races. Protéines 34%, lipides 9%, fibres 13%. L-Carnitine 400 mg/kg.'),

('Bab''in', 'Adulte Sans Céréales Canard','chien', 'all',    'adulte', 387,
 '[{"poids_kg":10,"grammes":163},{"poids_kg":15,"grammes":224},{"poids_kg":20,"grammes":279},{"poids_kg":30,"grammes":380}]',
 'Digestion sensible toutes races. Canard sans céréales.'),

-- ────────────────── BAB''IN NUTRITION — CHAT ───────────────────

('Bab''in', 'Chat Adulte Classique Poulet','chat', 'all', 'adulte', 386,
 '[{"poids_kg":2,"grammes":34},{"poids_kg":3,"grammes":45},{"poids_kg":4,"grammes":55},{"poids_kg":5,"grammes":64},{"poids_kg":6,"grammes":73}]',
 'Chat adulte 10 mois+. Poulet 70% protéines animales. Taurine 1200 mg/kg. Fabrication France.'),

('Bab''in', 'Chat Adulte Saumon',         'chat', 'all', 'adulte', 385,
 '[{"poids_kg":2,"grammes":34},{"poids_kg":3,"grammes":45},{"poids_kg":4,"grammes":55},{"poids_kg":5,"grammes":65}]',
 'Chat adulte. Saumon riche en oméga-3. Origine France Garantie.'),

('Bab''in', 'Chat Adulte Perte de Poids', 'chat', 'all', 'adulte', 316,
 '[{"poids_kg":2,"grammes":40},{"poids_kg":3,"grammes":53},{"poids_kg":4,"grammes":65},{"poids_kg":5,"grammes":76}]',
 'Chat adulte surpoids. Matières grasses réduites, fibres élevées.');

-- ────────────────── PÂTÉES / HUMIDE CHAT ──────────────────────
-- Densité typique pâtée : 70–100 kcal/100g (humidité 78–83%)
-- INSERT séparé pour spécifier type_aliment = 'pâtée'

INSERT INTO marques_aliments (marque, gamme, espece, taille_race, age_categorie, type_aliment, densite_kcal_100g, doses, notes) VALUES

('Royal Canin', 'Adult Instinctive Sauce (sachet)', 'chat', 'all', 'adulte', 'pâtée', 76,
 '[{"poids_kg":3,"grammes":140},{"poids_kg":4,"grammes":175},{"poids_kg":5,"grammes":205},{"poids_kg":6,"grammes":235}]',
 'Pâtée humide adulte 1–7 ans. Sachets 85g. Alimentation mixte recommandée.'),

('Royal Canin', 'Sterilised Adult Sauce (sachet)', 'chat', 'all', 'adulte', 'pâtée', 80,
 '[{"poids_kg":3,"grammes":148},{"poids_kg":4,"grammes":175},{"poids_kg":5,"grammes":201},{"poids_kg":6,"grammes":225}]',
 'Pâtée pour chat stérilisé adulte. Sachets 85g.'),

('Sheba', 'Classiques Sélection Boucher', 'chat', 'all', 'adulte', 'pâtée', 82,
 '[{"poids_kg":3,"grammes":128},{"poids_kg":4,"grammes":162},{"poids_kg":5,"grammes":193},{"poids_kg":6,"grammes":221}]',
 'Pâtée premium viandes sélectionnées. Barquettes 85g. Compléter avec croquettes.'),

('Sheba', 'Les Créations Sauce (sachet)', 'chat', 'all', 'adulte', 'pâtée', 78,
 '[{"poids_kg":3,"grammes":135},{"poids_kg":4,"grammes":169},{"poids_kg":5,"grammes":201},{"poids_kg":6,"grammes":231}]',
 'Sachets sauce premium. Portion 85g. Plusieurs variétés.'),

('Whiskas', 'Adult 1+ Terrine Volaille', 'chat', 'all', 'adulte', 'pâtée', 82,
 '[{"poids_kg":3,"grammes":128},{"poids_kg":4,"grammes":162},{"poids_kg":5,"grammes":193},{"poids_kg":6,"grammes":221}]',
 'Terrine humide chat adulte. Boîtes 400g. Protéines 9%, lipides 4%.'),

('Whiskas', 'Sachet Fraîcheur en Sauce', 'chat', 'all', 'adulte', 'pâtée', 75,
 '[{"poids_kg":3,"grammes":140},{"poids_kg":4,"grammes":175},{"poids_kg":5,"grammes":208},{"poids_kg":6,"grammes":240}]',
 'Sachets fraîcheur en sauce 100g. Plusieurs variétés.'),

('Felix', 'Le Pâté (sachets)', 'chat', 'all', 'adulte', 'pâtée', 78,
 '[{"poids_kg":3,"grammes":135},{"poids_kg":4,"grammes":170},{"poids_kg":5,"grammes":202},{"poids_kg":6,"grammes":231}]',
 'Sachets pâtée 85g. Bœuf, volaille, saumon. Alimentation mixte.'),

('Felix', 'Tendres Effilochés en Gelée', 'chat', 'all', 'adulte', 'pâtée', 68,
 '[{"poids_kg":3,"grammes":155},{"poids_kg":4,"grammes":194},{"poids_kg":5,"grammes":231},{"poids_kg":6,"grammes":265}]',
 'Effilochés en gelée, sachets 85g. Faible densité, bien hydratant.'),

('Hill''s', 'Science Plan Adult Wet Poulet', 'chat', 'all', 'adulte', 'pâtée', 90,
 '[{"poids_kg":3,"grammes":120},{"poids_kg":4,"grammes":150},{"poids_kg":5,"grammes":178},{"poids_kg":6,"grammes":204}]',
 'Pâtée adulte Science Plan boîtes 156g. ActivBiome+.'),

('Purina', 'Pro Plan Wet Adult Sensitive Saumon', 'chat', 'all', 'adulte', 'pâtée', 95,
 '[{"poids_kg":3,"grammes":114},{"poids_kg":4,"grammes":142},{"poids_kg":5,"grammes":169},{"poids_kg":6,"grammes":193}]',
 'Pâtée chat sensible saumon. Sachets 85g.'),

('Bab''in', 'Chat Terrine Poulet (pâtée)', 'chat', 'all', 'adulte', 'pâtée', 84,
 '[{"poids_kg":3,"grammes":125},{"poids_kg":4,"grammes":157},{"poids_kg":5,"grammes":187},{"poids_kg":6,"grammes":214}]',
 'Terrine humide chat adulte. Fabrication française. Poulet.'),

-- ────────────────── PÂTÉES / HUMIDE CHIEN ─────────────────────

('Royal Canin', 'Medium Adult Sauce (sachet)', 'chien', 'medium', 'adulte', 'pâtée', 88,
 '[{"poids_kg":11,"grammes":610},{"poids_kg":14,"grammes":730},{"poids_kg":20,"grammes":960},{"poids_kg":25,"grammes":1130}]',
 'Pâtée humide races moyennes adultes. Sachets 140g. Alimentation mixte.'),

('Purina', 'Pro Plan Wet Adult Medium Poulet', 'chien', 'medium', 'adulte', 'pâtée', 100,
 '[{"poids_kg":10,"grammes":630},{"poids_kg":15,"grammes":865},{"poids_kg":20,"grammes":1080},{"poids_kg":25,"grammes":1280}]',
 'Pâtée chien adulte races moyennes. Barquettes 150g.');
