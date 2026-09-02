-- Corrige les tables du carnet de santé (id TEXT PRIMARY KEY sans DEFAULT)
-- pour lesquelles au moins un formulaire du site (mes-patients côté
-- vétérinaire, association/animaux) insère une ligne sans jamais fournir
-- d'id : sans valeur ET sans défaut, l'insertion échoue systématiquement
-- (NOT NULL constraint sur id) pour tous les champs de l'enregistrement,
-- commentaires compris.
-- L'appli et les autres pages du site génèrent déjà leur propre id
-- (epoch millisecondes ou crypto.randomUUID()) et continuent de le faire ;
-- ce DEFAULT ne sert que de filet pour les appels qui l'omettent.
ALTER TABLE vaccinations      ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE traitements       ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE visites           ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE vermifuges        ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE antiparasitaires  ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE allergies         ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE poids             ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
