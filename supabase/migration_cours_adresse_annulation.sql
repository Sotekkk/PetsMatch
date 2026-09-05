-- Éducateur : adresse spécifique par cours (parcs…), limite d'annulation
-- client, et rappel RDV 30 min.

-- Adresse géolocalisée par défaut d'un cours du catalogue
ALTER TABLE prestations_education
  ADD COLUMN IF NOT EXISTS lieu_adresse TEXT,
  ADD COLUMN IF NOT EXISTS lieu_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS lieu_lng DOUBLE PRECISION;

-- Override du lieu pour un créneau / une séance précise
ALTER TABLE creneaux_pro
  ADD COLUMN IF NOT EXISTS lieu_adresse TEXT,
  ADD COLUMN IF NOT EXISTS lieu_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS lieu_lng DOUBLE PRECISION;

-- Géoloc du lieu d'un cours collectif (le champ texte `lieu` existe déjà)
ALTER TABLE cours_collectifs
  ADD COLUMN IF NOT EXISTS lieu_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS lieu_lng DOUBLE PRECISION;

-- Délai minimum avant le RDV en-deçà duquel le client ne peut plus
-- annuler / modifier lui-même. NULL / 0 = toujours possible.
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS annulation_limite_h SMALLINT;

COMMENT ON COLUMN user_profiles.annulation_limite_h IS
  'Heures avant le RDV en-deçà desquelles le client ne peut plus annuler/modifier. NULL/0 = toujours possible.';

-- Rappel 30 min (les colonnes reminder_24h_sent / reminder_48h_sent existent déjà)
ALTER TABLE rdv
  ADD COLUMN IF NOT EXISTS reminder_30min_sent BOOLEAN NOT NULL DEFAULT false;
