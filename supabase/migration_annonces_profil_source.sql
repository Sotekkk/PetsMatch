-- Ajoute profil_source pour distinguer annonces éleveur vs association
-- sur un même compte multi-profil (uid identique).
ALTER TABLE annonces ADD COLUMN IF NOT EXISTS profil_source TEXT DEFAULT 'eleveur';

-- Backfill best-effort : si le compte est UNIQUEMENT association (pas éleveur),
-- marque toutes ses annonces comme 'association'.
UPDATE annonces a
SET profil_source = 'association'
WHERE EXISTS (
  SELECT 1 FROM users u
  WHERE u.uid = a.uid_eleveur
    AND u.is_association = true
    AND (u.is_elevage IS NULL OR u.is_elevage = false)
);
