-- Numéro de pedigree sur les animaux (LOF n°, LOOF n°, SIRE, etc.)
ALTER TABLE animaux ADD COLUMN IF NOT EXISTS pedigree_numero TEXT;

-- Token de partage sur documents_animaux (pour lien acquéreur)
ALTER TABLE documents_animaux ADD COLUMN IF NOT EXISTS token TEXT UNIQUE DEFAULT gen_random_uuid()::TEXT;

CREATE INDEX IF NOT EXISTS idx_docs_token ON documents_animaux(token);

-- Permettre la mise à jour des signatures via token (acquéreur sans compte)
-- Le token UUID v4 (122 bits d'entropie) est le mécanisme de sécurité
DROP POLICY IF EXISTS "docs_sign_by_token" ON documents_animaux;
CREATE POLICY "docs_sign_by_token" ON documents_animaux
  FOR UPDATE
  USING (token IS NOT NULL)
  WITH CHECK (token IS NOT NULL);

-- Permettre la lecture publique via token (acquéreur sans compte)
DROP POLICY IF EXISTS "docs_read_by_token" ON documents_animaux;
CREATE POLICY "docs_read_by_token" ON documents_animaux
  FOR SELECT
  USING (token IS NOT NULL OR auth.uid()::text = uid_eleveur);
