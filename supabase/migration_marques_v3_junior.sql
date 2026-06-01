-- ─── Migration marques_aliments v3 — Aliments Junior / Puppy / Kitten ────────
-- Doses calculées depuis DER de croissance :
--   Chiot  : 70 × kg^0.75 × 2.0  (4–12 mois, activité modérée)
--   Chaton : 70 × kg^0.75 × 2.5  (2–12 mois)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO marques_aliments
  (marque, gamme, espece, taille_race, age_categorie, type_aliment, densite_kcal_100g, doses, notes)
VALUES

-- ─── CROQUETTES CHIOT ────────────────────────────────────────────────────────

-- Royal Canin Medium Puppy — 317 kcal/100g (2–12 mois, races moyennes)
('Royal Canin', 'Medium Puppy', 'chien', 'moyenne', 'junior', 'croquettes', 317,
 '[{"poids_kg":2,"grammes":74},{"poids_kg":5,"grammes":148},{"poids_kg":10,"grammes":248},{"poids_kg":20,"grammes":418},{"poids_kg":30,"grammes":566}]',
 'Races moyennes 11–25 kg adulte, jusqu''à 12 mois'),

-- Royal Canin Maxi Puppy — 303 kcal/100g (grandes races)
('Royal Canin', 'Maxi Puppy', 'chien', 'grande', 'junior', 'croquettes', 303,
 '[{"poids_kg":10,"grammes":260},{"poids_kg":20,"grammes":437},{"poids_kg":30,"grammes":592},{"poids_kg":40,"grammes":735}]',
 'Grandes races 26–44 kg adulte, jusqu''à 18 mois'),

-- Royal Canin Mini Puppy — 330 kcal/100g (petites races)
('Royal Canin', 'Mini Puppy', 'chien', 'petite', 'junior', 'croquettes', 330,
 '[{"poids_kg":1,"grammes":42},{"poids_kg":2,"grammes":71},{"poids_kg":3,"grammes":97},{"poids_kg":5,"grammes":142}]',
 'Petites races ≤10 kg adulte, jusqu''à 10 mois'),

-- Hill's Science Plan Puppy Medium — 352 kcal/100g
('Hill''s Science Plan', 'Puppy Medium Poulet', 'chien', 'moyenne', 'junior', 'croquettes', 352,
 '[{"poids_kg":2,"grammes":67},{"poids_kg":5,"grammes":133},{"poids_kg":10,"grammes":224},{"poids_kg":20,"grammes":376},{"poids_kg":30,"grammes":510}]',
 'Races moyennes, oméga-3 DHA'),

-- Hill's Science Plan Puppy Large Breed — 339 kcal/100g
('Hill''s Science Plan', 'Puppy Large Breed Poulet', 'chien', 'grande', 'junior', 'croquettes', 339,
 '[{"poids_kg":10,"grammes":233},{"poids_kg":20,"grammes":391},{"poids_kg":30,"grammes":530},{"poids_kg":40,"grammes":656}]',
 'Grandes races, contrôle croissance osseuse'),

-- Purina Pro Plan Puppy Medium — 367 kcal/100g
('Purina', 'Pro Plan Puppy Medium Poulet', 'chien', 'moyenne', 'junior', 'croquettes', 367,
 '[{"poids_kg":2,"grammes":64},{"poids_kg":5,"grammes":128},{"poids_kg":10,"grammes":215},{"poids_kg":20,"grammes":361},{"poids_kg":30,"grammes":489}]',
 'Optistart, DHA, immunité renforcée'),

-- Purina Pro Plan Puppy Large Breed — 355 kcal/100g
('Purina', 'Pro Plan Puppy Large Breed Poulet', 'chien', 'grande', 'junior', 'croquettes', 355,
 '[{"poids_kg":10,"grammes":222},{"poids_kg":20,"grammes":373},{"poids_kg":30,"grammes":505},{"poids_kg":40,"grammes":628}]',
 'Grandes races, ratio Ca/P contrôlé'),

-- Farmina N&D Puppy Ancestral Grain — 388 kcal/100g
('Farmina N&D', 'Ancestral Grain Puppy Medium Poulet', 'chien', 'moyenne', 'junior', 'croquettes', 388,
 '[{"poids_kg":2,"grammes":61},{"poids_kg":5,"grammes":121},{"poids_kg":10,"grammes":203},{"poids_kg":20,"grammes":341},{"poids_kg":30,"grammes":462}]',
 'Low grain, 60% protéines animales, DHA'),

('Farmina N&D', 'Grain Free Puppy Mini Poulet & Grenade', 'chien', 'petite', 'junior', 'croquettes', 400,
 '[{"poids_kg":1,"grammes":35},{"poids_kg":2,"grammes":59},{"poids_kg":3,"grammes":80},{"poids_kg":5,"grammes":117}]',
 'Sans céréales, petites races, antioxydants naturels'),

-- Josera Puppy — 395 kcal/100g
('Josera', 'Puppy', 'chien', NULL, 'junior', 'croquettes', 395,
 '[{"poids_kg":2,"grammes":60},{"poids_kg":5,"grammes":119},{"poids_kg":10,"grammes":199},{"poids_kg":20,"grammes":335},{"poids_kg":30,"grammes":454}]',
 'Toutes races, jusqu''à 12 mois'),

-- Brit Care Puppy Medium — 356 kcal/100g
('Brit Care', 'Grain Free Puppy Medium Poulet', 'chien', 'moyenne', 'junior', 'croquettes', 356,
 '[{"poids_kg":2,"grammes":66},{"poids_kg":5,"grammes":131},{"poids_kg":10,"grammes":221},{"poids_kg":20,"grammes":372},{"poids_kg":30,"grammes":504}]',
 'Sans céréales, prebiotiques, colostrum'),

-- Belcando Junior — 390 kcal/100g
('Belcando', 'Junior Grain Free Poulet', 'chien', NULL, 'junior', 'croquettes', 390,
 '[{"poids_kg":2,"grammes":60},{"poids_kg":5,"grammes":120},{"poids_kg":10,"grammes":202},{"poids_kg":20,"grammes":340},{"poids_kg":30,"grammes":460}]',
 'Sans céréales, toutes tailles jusqu''à 18 mois'),

-- Taste of the Wild Puppy High Prairie — 378 kcal/100g
('Taste of the Wild', 'High Prairie Puppy', 'chien', NULL, 'junior', 'croquettes', 378,
 '[{"poids_kg":2,"grammes":62},{"poids_kg":5,"grammes":124},{"poids_kg":10,"grammes":208},{"poids_kg":20,"grammes":350},{"poids_kg":30,"grammes":475}]',
 'Sans céréales, bison, bœuf rôti'),

-- Calibra Puppy — 393 kcal/100g
('Calibra', 'Life Puppy', 'chien', NULL, 'junior', 'croquettes', 393,
 '[{"poids_kg":2,"grammes":60},{"poids_kg":5,"grammes":119},{"poids_kg":10,"grammes":200},{"poids_kg":20,"grammes":336},{"poids_kg":30,"grammes":456}]',
 'Toutes races jusqu''à 18 mois'),

-- Advance Puppy — 384 kcal/100g
('Advance', 'Puppy All Breeds Poulet', 'chien', NULL, 'junior', 'croquettes', 384,
 '[{"poids_kg":2,"grammes":61},{"poids_kg":5,"grammes":122},{"poids_kg":10,"grammes":205},{"poids_kg":20,"grammes":344},{"poids_kg":30,"grammes":467}]',
 'Toutes races, DHA, colostrum bovin'),

-- ─── PÂTÉES CHIOT ────────────────────────────────────────────────────────────

-- Royal Canin Puppy Gravy — 85 kcal/100g
('Royal Canin', 'Puppy Sauce (sachet)', 'chien', NULL, 'junior', 'pâtée', 85,
 '[{"poids_kg":2,"grammes":276},{"poids_kg":5,"grammes":551},{"poids_kg":10,"grammes":927}]',
 'Sachet en sauce, complément ou ration seule chiot'),

-- Hill's Science Plan Puppy Wet — 90 kcal/100g
('Hill''s Science Plan', 'Puppy Healthy Development Poulet (boîte)', 'chien', NULL, 'junior', 'pâtée', 90,
 '[{"poids_kg":2,"grammes":261},{"poids_kg":5,"grammes":520},{"poids_kg":10,"grammes":875}]',
 'Boîte, DHA, croissance équilibrée'),

-- Purina Pro Plan Puppy Wet — 88 kcal/100g
('Purina', 'Pro Plan Puppy Poulet & Foie (sachet)', 'chien', NULL, 'junior', 'pâtée', 88,
 '[{"poids_kg":2,"grammes":267},{"poids_kg":5,"grammes":532},{"poids_kg":10,"grammes":895}]',
 'Sachet sauce, complément chiot'),

-- ─── CROQUETTES CHATON ───────────────────────────────────────────────────────

-- Royal Canin Kitten — 360 kcal/100g
('Royal Canin', 'Kitten', 'chat', NULL, 'junior', 'croquettes', 360,
 '[{"poids_kg":0.5,"grammes":29},{"poids_kg":1,"grammes":49},{"poids_kg":2,"grammes":82},{"poids_kg":3,"grammes":111},{"poids_kg":4,"grammes":138}]',
 'Chaton jusqu''à 12 mois'),

-- Royal Canin Kitten Sterilised — 346 kcal/100g
('Royal Canin', 'Kitten Sterilised', 'chat', NULL, 'junior', 'croquettes', 346,
 '[{"poids_kg":1,"grammes":51},{"poids_kg":2,"grammes":85},{"poids_kg":3,"grammes":115},{"poids_kg":4,"grammes":143}]',
 'Chaton stérilisé 6–12 mois'),

-- Hill's Science Plan Kitten — 375 kcal/100g
('Hill''s Science Plan', 'Kitten Poulet', 'chat', NULL, 'junior', 'croquettes', 375,
 '[{"poids_kg":0.5,"grammes":28},{"poids_kg":1,"grammes":47},{"poids_kg":2,"grammes":78},{"poids_kg":3,"grammes":106},{"poids_kg":4,"grammes":132}]',
 'DHA, antioxydants, immuno-defense'),

-- Purina Pro Plan Kitten — 390 kcal/100g
('Purina', 'Pro Plan Kitten Poulet (croquettes)', 'chat', NULL, 'junior', 'croquettes', 390,
 '[{"poids_kg":0.5,"grammes":27},{"poids_kg":1,"grammes":45},{"poids_kg":2,"grammes":75},{"poids_kg":3,"grammes":102},{"poids_kg":4,"grammes":127}]',
 'Optistart, DHA, start healthy — jusqu''à 12 mois'),

-- Orijen Kitten — 430 kcal/100g
('Orijen', 'Kitten', 'chat', NULL, 'junior', 'croquettes', 430,
 '[{"poids_kg":0.5,"grammes":24},{"poids_kg":1,"grammes":41},{"poids_kg":2,"grammes":68},{"poids_kg":3,"grammes":93},{"poids_kg":4,"grammes":115}]',
 'Biologically Appropriate, 85% viande, sans céréales'),

-- Brit Care Kitten — 363 kcal/100g
('Brit Care', 'Grain Free Kitten Healthy Growth', 'chat', NULL, 'junior', 'croquettes', 363,
 '[{"poids_kg":0.5,"grammes":29},{"poids_kg":1,"grammes":48},{"poids_kg":2,"grammes":81},{"poids_kg":3,"grammes":110},{"poids_kg":4,"grammes":136}]',
 'Sans céréales, colostrum, probiotiques'),

-- Advance Kitten — 378 kcal/100g
('Advance', 'Kitten Protect', 'chat', NULL, 'junior', 'croquettes', 378,
 '[{"poids_kg":0.5,"grammes":28},{"poids_kg":1,"grammes":46},{"poids_kg":2,"grammes":78},{"poids_kg":3,"grammes":105},{"poids_kg":4,"grammes":131}]',
 'Immunité et croissance, mères en gestation aussi'),

-- ─── PÂTÉES CHATON ───────────────────────────────────────────────────────────

-- Royal Canin Kitten Wet — 80 kcal/100g
('Royal Canin', 'Kitten en Sauce (sachet)', 'chat', NULL, 'junior', 'pâtée', 80,
 '[{"poids_kg":0.5,"grammes":130},{"poids_kg":1,"grammes":219},{"poids_kg":2,"grammes":368},{"poids_kg":3,"grammes":499}]',
 'Sachet en sauce, appétence élevée'),

-- Hill's Science Plan Kitten Wet — 76 kcal/100g
('Hill''s Science Plan', 'Kitten Healthy Development Poulet (boîte)', 'chat', NULL, 'junior', 'pâtée', 76,
 '[{"poids_kg":0.5,"grammes":137},{"poids_kg":1,"grammes":230},{"poids_kg":2,"grammes":387},{"poids_kg":3,"grammes":525}]',
 'Boîte, DHA, développement cognitif et oculaire'),

-- Purina ONE Kitten Wet — 82 kcal/100g
('Purina', 'ONE Kitten Poulet (sachet)', 'chat', NULL, 'junior', 'pâtée', 82,
 '[{"poids_kg":0.5,"grammes":127},{"poids_kg":1,"grammes":213},{"poids_kg":2,"grammes":358},{"poids_kg":3,"grammes":486}]',
 'Sachet sauce, grande distribution, DHA'),

-- Purina Pro Plan Kitten Wet — 78 kcal/100g
('Purina', 'Pro Plan Kitten Poulet & Foie (sachet)', 'chat', NULL, 'junior', 'pâtée', 78,
 '[{"poids_kg":0.5,"grammes":133},{"poids_kg":1,"grammes":224},{"poids_kg":2,"grammes":377},{"poids_kg":3,"grammes":512}]',
 'Sachet sauce, Optistart, DHA'),

-- Schesir Kitten Wet — 65 kcal/100g
('Schesir', 'Natural Kitten Chicken in Broth', 'chat', NULL, 'junior', 'pâtée', 65,
 '[{"poids_kg":0.5,"grammes":160},{"poids_kg":1,"grammes":269},{"poids_kg":2,"grammes":453},{"poids_kg":3,"grammes":614}]',
 'Poulet en bouillon naturel, sans conservateurs, < 12 mois'),

-- Almo Nature Kitten — 70 kcal/100g
('Almo Nature', 'HFC Natural Kitten Poulet', 'chat', NULL, 'junior', 'pâtée', 70,
 '[{"poids_kg":0.5,"grammes":149},{"poids_kg":1,"grammes":250},{"poids_kg":2,"grammes":420},{"poids_kg":3,"grammes":570}]',
 'Ingrédients biologically appropriate, chaton'),

-- Edgard & Cooper Kitten — 72 kcal/100g
('Edgard & Cooper', 'Poulet frais Kitten (sachet)', 'chat', NULL, 'junior', 'pâtée', 72,
 '[{"poids_kg":0.5,"grammes":145},{"poids_kg":1,"grammes":243},{"poids_kg":2,"grammes":408},{"poids_kg":3,"grammes":554}]',
 'Sans ingrédients artificiels, chaton naturel')

;
