-- Description de la maladie associée à un traitement (affichée sous le
-- champ "Type" dans la fiche santé, app et site web).
ALTER TABLE traitements
  ADD COLUMN IF NOT EXISTS description_maladie TEXT;
