-- ─── Migration marques_aliments v2 ─────────────────────────────────────────
-- Nouvelles marques : zooplus.fr + animalis.fr
-- kcal/100g vérifiés via sources fabricants / sites marchands
-- doses calculées depuis DER (70×kg^0.75 × 1.6 adulte chien / 1.4 chat)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO marques_aliments
  (marque, gamme, espece, taille_race, age_categorie, type_aliment, densite_kcal_100g, doses, notes)
VALUES

-- ─── CROQUETTES CHIEN ────────────────────────────────────────────────────────

-- Taste of the Wild — 366 kcal/100g (grain-free, bison & venaison)
('Taste of the Wild', 'High Prairie Adult', 'chien', NULL, 'adulte', 'croquettes', 366,
 '[{"poids_kg":2,"grammes":51},{"poids_kg":5,"grammes":102},{"poids_kg":10,"grammes":172},{"poids_kg":20,"grammes":289},{"poids_kg":30,"grammes":393},{"poids_kg":40,"grammes":489}]',
 'Sans céréales, protéines bison et venaison'),

('Taste of the Wild', 'Pacific Stream Adult (Saumon)', 'chien', NULL, 'adulte', 'croquettes', 361,
 '[{"poids_kg":2,"grammes":52},{"poids_kg":5,"grammes":104},{"poids_kg":10,"grammes":175},{"poids_kg":20,"grammes":293},{"poids_kg":30,"grammes":398},{"poids_kg":40,"grammes":497}]',
 'Sans céréales, saumon sauvage'),

-- Farmina N&D — 368 kcal/100g
('Farmina N&D', 'Ancestral Grain Medium Poulet', 'chien', 'moyenne', 'adulte', 'croquettes', 368,
 '[{"poids_kg":5,"grammes":102},{"poids_kg":10,"grammes":171},{"poids_kg":20,"grammes":288},{"poids_kg":30,"grammes":390},{"poids_kg":40,"grammes":487}]',
 'Low grain, 60% protéines animales'),

('Farmina N&D', 'Ancestral Grain Mini Poulet', 'chien', 'petite', 'adulte', 'croquettes', 380,
 '[{"poids_kg":1,"grammes":29},{"poids_kg":2,"grammes":49},{"poids_kg":5,"grammes":99},{"poids_kg":10,"grammes":166}]',
 'Low grain, petites races'),

('Farmina N&D', 'Grain Free Large Agneau', 'chien', 'grande', 'adulte', 'croquettes', 364,
 '[{"poids_kg":10,"grammes":173},{"poids_kg":20,"grammes":291},{"poids_kg":30,"grammes":395},{"poids_kg":40,"grammes":493},{"poids_kg":50,"grammes":585}]',
 'Sans céréales, grandes races'),

-- Josera — 383 kcal/100g
('Josera', 'Nature Energetic', 'chien', 'moyenne', 'adulte', 'croquettes', 383,
 '[{"poids_kg":5,"grammes":98},{"poids_kg":10,"grammes":165},{"poids_kg":20,"grammes":277},{"poids_kg":30,"grammes":375},{"poids_kg":40,"grammes":468}]',
 'Riche en énergie, chiens actifs'),

('Josera', 'SensiCare Adult', 'chien', 'moyenne', 'adulte', 'croquettes', 356,
 '[{"poids_kg":5,"grammes":105},{"poids_kg":10,"grammes":177},{"poids_kg":20,"grammes":298},{"poids_kg":30,"grammes":404}]',
 'Digestion sensible, sans gluten'),

-- Belcando — 388 kcal/100g
('Belcando', 'Adult Active', 'chien', NULL, 'adulte', 'croquettes', 388,
 '[{"poids_kg":5,"grammes":97},{"poids_kg":10,"grammes":163},{"poids_kg":20,"grammes":273},{"poids_kg":30,"grammes":370},{"poids_kg":40,"grammes":462}]',
 'Chiens très actifs, haute énergie'),

('Belcando', 'Adult Grain Free', 'chien', NULL, 'adulte', 'croquettes', 378,
 '[{"poids_kg":5,"grammes":99},{"poids_kg":10,"grammes":167},{"poids_kg":20,"grammes":280},{"poids_kg":30,"grammes":380},{"poids_kg":40,"grammes":474}]',
 'Sans céréales'),

-- Nutro — 365 kcal/100g
('Nutro', 'Grain Free Large Breed Agneau', 'chien', 'grande', 'adulte', 'croquettes', 365,
 '[{"poids_kg":10,"grammes":173},{"poids_kg":20,"grammes":290},{"poids_kg":30,"grammes":393},{"poids_kg":40,"grammes":491},{"poids_kg":50,"grammes":583}]',
 'Sans céréales, grandes races, ingrédients limités'),

('Nutro', 'Adult Small Breed Poulet', 'chien', 'petite', 'adulte', 'croquettes', 378,
 '[{"poids_kg":1,"grammes":30},{"poids_kg":2,"grammes":50},{"poids_kg":5,"grammes":99},{"poids_kg":10,"grammes":167}]',
 'Petites races'),

-- Brit Care — 370 kcal/100g
('Brit Care', 'Hypoallergenic Adult Medium Agneau', 'chien', 'moyenne', 'adulte', 'croquettes', 370,
 '[{"poids_kg":5,"grammes":101},{"poids_kg":10,"grammes":171},{"poids_kg":20,"grammes":286},{"poids_kg":30,"grammes":388},{"poids_kg":40,"grammes":485}]',
 'Hypoallergénique, agneau source unique'),

('Brit Care', 'Grain Free Adult Large Poulet', 'chien', 'grande', 'adulte', 'croquettes', 362,
 '[{"poids_kg":10,"grammes":174},{"poids_kg":20,"grammes":293},{"poids_kg":30,"grammes":397},{"poids_kg":40,"grammes":495}]',
 'Sans céréales, grandes races'),

-- Advance — 384 kcal/100g
('Advance', 'Active Defense Adult Medium', 'chien', 'moyenne', 'adulte', 'croquettes', 384,
 '[{"poids_kg":5,"grammes":98},{"poids_kg":10,"grammes":164},{"poids_kg":20,"grammes":276},{"poids_kg":30,"grammes":374},{"poids_kg":40,"grammes":467}]',
 'Protection active, races moyennes'),

('Advance', 'Adult Mini Sensitive', 'chien', 'petite', 'adulte', 'croquettes', 373,
 '[{"poids_kg":1,"grammes":30},{"poids_kg":2,"grammes":51},{"poids_kg":5,"grammes":101},{"poids_kg":10,"grammes":169}]',
 'Petites races, digestion sensible'),

-- Virbac HPM — 370 kcal/100g (vétérinaire)
('Virbac', 'Veterinary HPM Adult Dog Neutered', 'chien', NULL, 'adulte', 'croquettes', 350,
 '[{"poids_kg":5,"grammes":107},{"poids_kg":10,"grammes":180},{"poids_kg":20,"grammes":303},{"poids_kg":30,"grammes":411}]',
 'Stérilisé/castré, faible teneur glucides'),

('Virbac', 'Veterinary HPM Adult Dog', 'chien', NULL, 'adulte', 'croquettes', 370,
 '[{"poids_kg":5,"grammes":101},{"poids_kg":10,"grammes":171},{"poids_kg":20,"grammes":286},{"poids_kg":30,"grammes":388},{"poids_kg":40,"grammes":485}]',
 'Faible en glucides, haute protéine'),

-- Calibra — 420 kcal/100g (haute énergie)
('Calibra', 'Dog Expert Nutrition Energy', 'chien', NULL, 'adulte', 'croquettes', 420,
 '[{"poids_kg":5,"grammes":89},{"poids_kg":10,"grammes":150},{"poids_kg":20,"grammes":252},{"poids_kg":30,"grammes":342},{"poids_kg":40,"grammes":427}]',
 'Haute énergie, chiens de travail / très actifs'),

('Calibra', 'Dog Life Stage Adult Medium', 'chien', 'moyenne', 'adulte', 'croquettes', 370,
 '[{"poids_kg":5,"grammes":101},{"poids_kg":10,"grammes":171},{"poids_kg":20,"grammes":286},{"poids_kg":30,"grammes":388}]',
 NULL),

-- Pedigree — 334 kcal/100g
('Pedigree', 'Adult au Poulet et Légumes', 'chien', NULL, 'adulte', 'croquettes', 334,
 '[{"poids_kg":5,"grammes":112},{"poids_kg":10,"grammes":189},{"poids_kg":20,"grammes":317},{"poids_kg":30,"grammes":430},{"poids_kg":40,"grammes":537}]',
 'Entrée de gamme, grande diffusion'),

-- Wolfsblut — 350 kcal/100g
('Wolfsblut', 'Wild Duck & Potato Adult', 'chien', NULL, 'adulte', 'croquettes', 350,
 '[{"poids_kg":5,"grammes":107},{"poids_kg":10,"grammes":180},{"poids_kg":20,"grammes":303},{"poids_kg":30,"grammes":411},{"poids_kg":40,"grammes":512}]',
 'Sans céréales, canard sauvage'),

-- ─── CROQUETTES CHAT ────────────────────────────────────────────────────────

-- Josera Daily Cat — 386 kcal/100g
('Josera', 'Daily Cat', 'chat', NULL, 'adulte', 'croquettes', 386,
 '[{"poids_kg":3,"grammes":58},{"poids_kg":4,"grammes":72},{"poids_kg":5,"grammes":85},{"poids_kg":6,"grammes":97},{"poids_kg":7,"grammes":109}]',
 NULL),

('Josera', 'JosiCat Kitten', 'chat', NULL, 'junior', 'croquettes', 418,
 '[{"poids_kg":2,"grammes":50},{"poids_kg":3,"grammes":66},{"poids_kg":4,"grammes":80}]',
 'Chaton jusqu''à 12 mois'),

('Josera', 'Happy Cat Senior', 'chat', NULL, 'senior', 'croquettes', 346,
 '[{"poids_kg":3,"grammes":65},{"poids_kg":4,"grammes":80},{"poids_kg":5,"grammes":94},{"poids_kg":6,"grammes":108}]',
 'Chat senior 8+ ans'),

-- Sanabelle — 360 / 346 kcal/100g
('Sanabelle', 'Adult Indoor', 'chat', NULL, 'adulte', 'croquettes', 360,
 '[{"poids_kg":3,"grammes":62},{"poids_kg":4,"grammes":77},{"poids_kg":5,"grammes":91},{"poids_kg":6,"grammes":104}]',
 'Chats d''intérieur'),

('Sanabelle', 'Adult Sterilised', 'chat', NULL, 'adulte', 'croquettes', 346,
 '[{"poids_kg":3,"grammes":64},{"poids_kg":4,"grammes":80},{"poids_kg":5,"grammes":95},{"poids_kg":6,"grammes":109}]',
 'Stérilisés, contrôle du poids'),

('Sanabelle', 'Kitten', 'chat', NULL, 'junior', 'croquettes', 418,
 '[{"poids_kg":1,"grammes":45},{"poids_kg":2,"grammes":63},{"poids_kg":3,"grammes":79}]',
 'Chaton < 12 mois'),

-- Brit Care chat — 340 kcal/100g
('Brit Care', 'Sterilised Weight Control', 'chat', NULL, 'adulte', 'croquettes', 340,
 '[{"poids_kg":3,"grammes":66},{"poids_kg":4,"grammes":81},{"poids_kg":5,"grammes":96},{"poids_kg":6,"grammes":110}]',
 'Stérilisés, contrôle du poids'),

('Brit Care', 'Grain Free Adult Indoor Herring', 'chat', NULL, 'adulte', 'croquettes', 363,
 '[{"poids_kg":3,"grammes":61},{"poids_kg":4,"grammes":76},{"poids_kg":5,"grammes":90},{"poids_kg":6,"grammes":104}]',
 'Sans céréales, intérieur, hareng'),

-- Specific — 372 kcal/100g (vétérinaire, hypoallergénique)
('Specific', 'FDD-HY Food Allergen Management', 'chat', NULL, 'adulte', 'croquettes', 372,
 '[{"poids_kg":3,"grammes":60},{"poids_kg":4,"grammes":74},{"poids_kg":5,"grammes":88},{"poids_kg":6,"grammes":101}]',
 'Vétérinaire, gestion allergies alimentaires'),

-- Farmina N&D chat
('Farmina N&D', 'Ancestral Grain Adult Poulet', 'chat', NULL, 'adulte', 'croquettes', 379,
 '[{"poids_kg":3,"grammes":59},{"poids_kg":4,"grammes":73},{"poids_kg":5,"grammes":86},{"poids_kg":6,"grammes":99}]',
 'Low grain, chat adulte'),

('Farmina N&D', 'Grain Free Kitten Poulet', 'chat', NULL, 'junior', 'croquettes', 395,
 '[{"poids_kg":1,"grammes":47},{"poids_kg":2,"grammes":62},{"poids_kg":3,"grammes":75}]',
 'Sans céréales, chaton'),

-- Virbac chat
('Virbac', 'Veterinary HPM Adult Cat Neutered', 'chat', NULL, 'adulte', 'croquettes', 355,
 '[{"poids_kg":3,"grammes":63},{"poids_kg":4,"grammes":78},{"poids_kg":5,"grammes":92},{"poids_kg":6,"grammes":106}]',
 'Stérilisé/castré, faible en glucides'),

-- ─── PÂTÉES CHIEN ───────────────────────────────────────────────────────────

-- Animonda GranCarno — 110 kcal/100g
('Animonda', 'GranCarno Adult Bœuf', 'chien', NULL, 'adulte', 'pâtée', 110,
 '[{"poids_kg":5,"grammes":341},{"poids_kg":10,"grammes":574},{"poids_kg":20,"grammes":963},{"poids_kg":30,"grammes":1306}]',
 'Pâtée haut de gamme, 70% viande'),

('Animonda', 'GranCarno Adult Agneau', 'chien', NULL, 'adulte', 'pâtée', 107,
 '[{"poids_kg":5,"grammes":350},{"poids_kg":10,"grammes":590},{"poids_kg":20,"grammes":990}]',
 'Pâtée agneau, protéine unique'),

-- Schesir — 70-75 kcal/100g
('Schesir', 'Natural Chicken in Broth', 'chien', NULL, 'adulte', 'pâtée', 72,
 '[{"poids_kg":5,"grammes":521},{"poids_kg":10,"grammes":876},{"poids_kg":20,"grammes":1471}]',
 'Poulet en bouillon naturel, sans conservateurs'),

('Schesir', 'Natural Tuna in Broth', 'chien', NULL, 'adulte', 'pâtée', 68,
 '[{"poids_kg":5,"grammes":551},{"poids_kg":10,"grammes":927},{"poids_kg":20,"grammes":1557}]',
 'Thon en bouillon, faible teneur en graisse'),

-- Almo Nature — 53-60 kcal/100g
('Almo Nature', 'HFC Natural Poulet', 'chien', NULL, 'adulte', 'pâtée', 58,
 '[{"poids_kg":5,"grammes":647},{"poids_kg":10,"grammes":1088},{"poids_kg":20,"grammes":1827}]',
 'Très faible densité, idéal pour compléter croquettes'),

('Almo Nature', 'HFC Natural Thon & Saumon', 'chien', NULL, 'adulte', 'pâtée', 55,
 '[{"poids_kg":5,"grammes":682},{"poids_kg":10,"grammes":1147},{"poids_kg":20,"grammes":1925}]',
 NULL),

-- True Instinct — 80 kcal/100g
('True Instinct', 'No Grain Poulet & Dinde (sachet)', 'chien', NULL, 'adulte', 'pâtée', 80,
 '[{"poids_kg":5,"grammes":469},{"poids_kg":10,"grammes":789},{"poids_kg":20,"grammes":1324}]',
 'Sachet sans céréales, haute teneur viande'),

-- Vitakraft — 85 kcal/100g
('Vitakraft', 'Meat Me bœuf', 'chien', NULL, 'adulte', 'pâtée', 85,
 '[{"poids_kg":5,"grammes":441},{"poids_kg":10,"grammes":742},{"poids_kg":20,"grammes":1246}]',
 'Pâtée monoprotéine bœuf'),

-- ─── PÂTÉES CHAT ────────────────────────────────────────────────────────────

-- Animonda Carny cat — 75 kcal/100g
('Animonda', 'Carny Adult Bœuf & Poulet', 'chat', NULL, 'adulte', 'pâtée', 75,
 '[{"poids_kg":3,"grammes":297},{"poids_kg":4,"grammes":369},{"poids_kg":5,"grammes":437},{"poids_kg":6,"grammes":501}]',
 'Pâtée haut de gamme, >80% viande'),

('Animonda', 'Carny Kitten', 'chat', NULL, 'junior', 'pâtée', 80,
 '[{"poids_kg":1,"grammes":200},{"poids_kg":2,"grammes":275},{"poids_kg":3,"grammes":340}]',
 'Chaton jusqu''à 12 mois'),

('Animonda', 'Carny Adult Sterilized', 'chat', NULL, 'adulte', 'pâtée', 68,
 '[{"poids_kg":3,"grammes":328},{"poids_kg":4,"grammes":407},{"poids_kg":5,"grammes":482},{"poids_kg":6,"grammes":553}]',
 'Stérilisés/castrés'),

-- Schesir cat — 65 kcal/100g
('Schesir', 'Natural Chicken in Broth', 'chat', NULL, 'adulte', 'pâtée', 65,
 '[{"poids_kg":3,"grammes":343},{"poids_kg":4,"grammes":426},{"poids_kg":5,"grammes":505},{"poids_kg":6,"grammes":578}]',
 'Poulet en bouillon naturel'),

('Schesir', 'Natural Tuna in Broth', 'chat', NULL, 'adulte', 'pâtée', 58,
 '[{"poids_kg":3,"grammes":384},{"poids_kg":4,"grammes":477},{"poids_kg":5,"grammes":565},{"poids_kg":6,"grammes":648}]',
 'Thon en bouillon'),

('Schesir', 'in Coconut Milk Chicken', 'chat', NULL, 'adulte', 'pâtée', 72,
 '[{"poids_kg":3,"grammes":310},{"poids_kg":4,"grammes":385},{"poids_kg":5,"grammes":456},{"poids_kg":6,"grammes":522}]',
 'Poulet au lait de coco, sans conservateurs'),

-- Almo Nature chat — 55 kcal/100g
('Almo Nature', 'Classic Poulet & Riz', 'chat', NULL, 'adulte', 'pâtée', 73,
 '[{"poids_kg":3,"grammes":305},{"poids_kg":4,"grammes":379},{"poids_kg":5,"grammes":449},{"poids_kg":6,"grammes":515}]',
 NULL),

('Almo Nature', 'HFC Natural Poulet', 'chat', NULL, 'adulte', 'pâtée', 55,
 '[{"poids_kg":3,"grammes":405},{"poids_kg":4,"grammes":503},{"poids_kg":5,"grammes":596},{"poids_kg":6,"grammes":684}]',
 'Très humide, haute palatabilité'),

-- True Instinct chat
('True Instinct', 'No Grain Poulet & Thon (sachet)', 'chat', NULL, 'adulte', 'pâtée', 68,
 '[{"poids_kg":3,"grammes":328},{"poids_kg":4,"grammes":407},{"poids_kg":5,"grammes":482},{"poids_kg":6,"grammes":553}]',
 'Sans céréales, sachet'),

-- Edgard & Cooper — 65 kcal/100g
('Edgard & Cooper', 'Poulet frais & Saumon sauvage', 'chat', NULL, 'adulte', 'pâtée', 65,
 '[{"poids_kg":3,"grammes":343},{"poids_kg":4,"grammes":426},{"poids_kg":5,"grammes":505},{"poids_kg":6,"grammes":578}]',
 'Ingrédients naturels, sans colorants'),

-- Purina ONE cat pâtée — 78 kcal/100g
('Purina', 'ONE Adult Poulet & Carottes', 'chat', NULL, 'adulte', 'pâtée', 78,
 '[{"poids_kg":3,"grammes":286},{"poids_kg":4,"grammes":355},{"poids_kg":5,"grammes":421},{"poids_kg":6,"grammes":482}]',
 'Sachet sauce, grande distribution'),

-- Virbac HPM pâtée
('Virbac', 'Veterinary HPM Adult Cat Wet', 'chat', NULL, 'adulte', 'pâtée', 82,
 '[{"poids_kg":3,"grammes":272},{"poids_kg":4,"grammes":338},{"poids_kg":5,"grammes":400},{"poids_kg":6,"grammes":459}]',
 'Vétérinaire, faible en glucides'),

-- ─── GRANULÉS CHEVAL ────────────────────────────────────────────────────────

-- Cavalor — 287 kcal/100g (≈ 12 MJ/kg EM)
('Cavalor', 'Strucomix Original', 'cheval', NULL, 'adulte', 'croquettes', 270,
 '[{"poids_kg":200,"grammes":1500},{"poids_kg":400,"grammes":2500},{"poids_kg":500,"grammes":3000},{"poids_kg":600,"grammes":3500}]',
 'Muesli fibres, travail léger à modéré'),

('Cavalor', 'Endurix (endurance)', 'cheval', NULL, 'adulte', 'croquettes', 295,
 '[{"poids_kg":400,"grammes":3000},{"poids_kg":500,"grammes":3500},{"poids_kg":600,"grammes":4000}]',
 'Travail intense, endurance — max 2.5 kg/repas'),

-- Spillers — 287 kcal/100g
('Spillers', 'Conditioning Cubes', 'cheval', NULL, 'adulte', 'croquettes', 287,
 '[{"poids_kg":200,"grammes":1000},{"poids_kg":400,"grammes":2000},{"poids_kg":500,"grammes":2500},{"poids_kg":600,"grammes":3000}]',
 'Cube conditioning, 11.9 MJ/kg EM — max 2.5 kg/repas'),

-- Equifirst — 300 kcal/100g
('Equifirst', 'Sport Müsli', 'cheval', NULL, 'adulte', 'croquettes', 300,
 '[{"poids_kg":400,"grammes":2500},{"poids_kg":500,"grammes":3000},{"poids_kg":600,"grammes":3500}]',
 'Muesli sport, 12.5 MJ/kg EM'),

('Equifirst', 'Condition Mix', 'cheval', NULL, 'adulte', 'croquettes', 285,
 '[{"poids_kg":400,"grammes":2000},{"poids_kg":500,"grammes":2500},{"poids_kg":600,"grammes":3000}]',
 'Entretien et condition physique'),

-- ─── GRANULÉS LAPIN ─────────────────────────────────────────────────────────

-- Oxbow — 307 kcal/100g
('Oxbow', 'Essentials Adult Rabbit', 'lapin', NULL, 'adulte', 'croquettes', 307,
 '[{"poids_kg":1,"grammes":25},{"poids_kg":2,"grammes":40},{"poids_kg":3,"grammes":55},{"poids_kg":4,"grammes":65}]',
 'Pellets timothy grass, sans mélasse'),

('Oxbow', 'Garden Select Adult Rabbit', 'lapin', NULL, 'adulte', 'croquettes', 298,
 '[{"poids_kg":1,"grammes":25},{"poids_kg":2,"grammes":42},{"poids_kg":3,"grammes":57},{"poids_kg":4,"grammes":68}]',
 'Pellets à base de graminées, légumes déshydratés'),

-- Versele-Laga Cuni Nature — 273 kcal/100g
('Versele-Laga', 'Cuni Nature Adult', 'lapin', NULL, 'adulte', 'croquettes', 273,
 '[{"poids_kg":1,"grammes":28},{"poids_kg":2,"grammes":45},{"poids_kg":3,"grammes":60},{"poids_kg":4,"grammes":72}]',
 'Pellets naturels, foin de timothy inclus'),

('Versele-Laga', 'Cuni Junior (< 6 mois)', 'lapin', NULL, 'junior', 'croquettes', 290,
 '[{"poids_kg":1,"grammes":30},{"poids_kg":1.5,"grammes":42},{"poids_kg":2,"grammes":52}]',
 'Lapereau jusqu''à 6 mois'),

-- Cunipic — 295 kcal/100g
('Cunipic', 'Premium Adult Rabbit', 'lapin', NULL, 'adulte', 'croquettes', 295,
 '[{"poids_kg":1,"grammes":26},{"poids_kg":2,"grammes":42},{"poids_kg":3,"grammes":56},{"poids_kg":4,"grammes":68}]',
 'Riche en fibres, sans sucres ajoutés')

;
