-- ══════════════════════════════════════════════════════════════════════════
-- Ajout de la couleur des yeux, en miroir de la couleur/robe existante,
-- partout où celle-ci est déjà présente (fiche animal, annonces, alertes
-- perdus/trouvés).
-- ══════════════════════════════════════════════════════════════════════════

ALTER TABLE animaux        ADD COLUMN IF NOT EXISTS couleur_yeux TEXT;
ALTER TABLE annonces       ADD COLUMN IF NOT EXISTS couleur_yeux TEXT;
ALTER TABLE annonces       ADD COLUMN IF NOT EXISTS mere_couleur_yeux TEXT;
ALTER TABLE annonces       ADD COLUMN IF NOT EXISTS pere_couleur_yeux TEXT;
ALTER TABLE alertes_perdus ADD COLUMN IF NOT EXISTS couleur_yeux TEXT;
ALTER TABLE animaux_trouves ADD COLUMN IF NOT EXISTS couleur_yeux TEXT;

-- Vérification
SELECT table_name, column_name FROM information_schema.columns
WHERE column_name = 'couleur_yeux'
ORDER BY table_name;
