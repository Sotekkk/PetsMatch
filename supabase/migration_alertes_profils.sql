-- Ajout profile_id sur alertes_perdus et animaux_trouves
-- Exécuter les deux blocs séparément si erreur

ALTER TABLE alertes_perdus
  ADD COLUMN IF NOT EXISTS profile_id UUID;

ALTER TABLE animaux_trouves
  ADD COLUMN IF NOT EXISTS profile_id UUID;

CREATE INDEX IF NOT EXISTS idx_alertes_perdus_profile_id ON alertes_perdus(profile_id);

CREATE INDEX IF NOT EXISTS idx_animaux_trouves_profile_id ON animaux_trouves(profile_id);
