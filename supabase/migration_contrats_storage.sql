-- Bucket public pour les contrats signés
INSERT INTO storage.buckets (id, name, public)
VALUES ('contrats', 'contrats', true)
ON CONFLICT (id) DO NOTHING;

-- Lecture publique (pour partager le lien)
CREATE POLICY IF NOT EXISTS "contrats_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'contrats');

-- Écriture authentifiée (depuis le navigateur via anon key)
CREATE POLICY IF NOT EXISTS "contrats_anon_insert"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'contrats');

CREATE POLICY IF NOT EXISTS "contrats_anon_update"
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'contrats');
