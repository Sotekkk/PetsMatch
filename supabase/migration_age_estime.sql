-- Migration : âge estimé pour les animaux d'association dont la date de naissance exacte est inconnue

-- animaux : la date_naissance stockée devient une date approximative quand age_estime = true
ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS age_estime BOOLEAN DEFAULT FALSE;

-- annonces : copie du flag depuis l'animal lié, pour affichage côté adoptants (site + application)
ALTER TABLE annonces
  ADD COLUMN IF NOT EXISTS age_estime BOOLEAN DEFAULT FALSE;
