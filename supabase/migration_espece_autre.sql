-- Migration : précision texte libre quand l'espèce sélectionnée est "autre"

ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS espece_autre TEXT;

ALTER TABLE annonces
  ADD COLUMN IF NOT EXISTS espece_autre TEXT;
