-- Politiques Storage pour le bucket "petsmatch" (anon key — sans Supabase Auth)
-- Le projet utilise Firebase Auth + clé anon Supabase → pas de auth.uid() disponible
-- Toutes les opérations sont autorisées pour l'anon sur les buckets petsmatch et documents

-- Bucket petsmatch (photos de profil, bannières)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('petsmatch', 'petsmatch', true, 10485760, ARRAY['image/jpeg','image/png','image/webp','image/gif','application/pdf'])
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 10485760,
  allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp','image/gif','application/pdf'];

-- Policies SELECT (lecture publique)
DROP POLICY IF EXISTS "petsmatch_public_select" ON storage.objects;
CREATE POLICY "petsmatch_public_select" ON storage.objects
  FOR SELECT USING (bucket_id = 'petsmatch');

-- Policies INSERT (upload anon autorisé)
DROP POLICY IF EXISTS "petsmatch_anon_insert" ON storage.objects;
CREATE POLICY "petsmatch_anon_insert" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'petsmatch');

-- Policies UPDATE (upsert anon autorisé)
DROP POLICY IF EXISTS "petsmatch_anon_update" ON storage.objects;
CREATE POLICY "petsmatch_anon_update" ON storage.objects
  FOR UPDATE USING (bucket_id = 'petsmatch') WITH CHECK (bucket_id = 'petsmatch');

-- Policies DELETE
DROP POLICY IF EXISTS "petsmatch_anon_delete" ON storage.objects;
CREATE POLICY "petsmatch_anon_delete" ON storage.objects
  FOR DELETE USING (bucket_id = 'petsmatch');
