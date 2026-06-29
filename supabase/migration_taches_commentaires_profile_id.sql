-- Migration: profil_id sur taches_elevage et tache_commentaires

-- taches_elevage : eleveur_profile_id (IF NOT EXISTS — peut déjà exister)
ALTER TABLE taches_elevage
  ADD COLUMN IF NOT EXISTS eleveur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE taches_elevage t
SET eleveur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = t.uid_eleveur
  AND up.is_main = true
  AND t.eleveur_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS taches_elevage_eleveur_profile_id_idx ON taches_elevage(eleveur_profile_id);

-- tache_commentaires : auteur_profile_id (nouvelle colonne)
ALTER TABLE tache_commentaires
  ADD COLUMN IF NOT EXISTS auteur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE tache_commentaires c
SET auteur_profile_id = up.id
FROM user_profiles up
WHERE up.uid = c.uid_auteur
  AND up.is_main = true
  AND c.auteur_profile_id IS NULL;

CREATE INDEX IF NOT EXISTS tache_commentaires_auteur_profile_id_idx ON tache_commentaires(auteur_profile_id);
