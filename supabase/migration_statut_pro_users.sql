-- Migration : ajouter statut_pro à la table users (profils primaires)
-- + certifications et rayon_intervention si manquants (colonnes utilisées dans l'admin)

ALTER TABLE users ADD COLUMN IF NOT EXISTS statut_pro TEXT DEFAULT 'actif';
ALTER TABLE users ADD COLUMN IF NOT EXISTS rayon_intervention INTEGER DEFAULT 20;
ALTER TABLE users ADD COLUMN IF NOT EXISTS especes_acceptees TEXT[] DEFAULT '{}';
ALTER TABLE users ADD COLUMN IF NOT EXISTS certifications JSONB DEFAULT '[]';
ALTER TABLE users ADD COLUMN IF NOT EXISTS name_elevage TEXT;

-- Mettre les pros existants actifs par défaut
UPDATE users SET statut_pro = 'actif' WHERE cat_pro IS NOT NULL AND statut_pro IS NULL;

CREATE INDEX IF NOT EXISTS idx_users_statut_pro ON users(statut_pro);
CREATE INDEX IF NOT EXISTS idx_users_cat_pro ON users(cat_pro);
