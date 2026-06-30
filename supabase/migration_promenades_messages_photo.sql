-- ============================================================
-- Migration : Photos + message nullable dans promenades_messages
-- Date      : 2026-06-30
-- ============================================================

-- Ajouter colonne image_url et rendre message nullable (photo seule possible)
ALTER TABLE promenades_messages
  ADD COLUMN IF NOT EXISTS image_url TEXT,
  ALTER COLUMN message DROP NOT NULL;

-- Contrainte : au moins message ou image_url doit être présent
ALTER TABLE promenades_messages
  DROP CONSTRAINT IF EXISTS prom_msg_content_check;

ALTER TABLE promenades_messages
  ADD CONSTRAINT prom_msg_content_check
    CHECK (message IS NOT NULL OR image_url IS NOT NULL);

-- ── Storage bucket pour les photos de groupes de promenade ────────────────────
-- À exécuter une seule fois via l'interface Supabase Storage ou ici :
INSERT INTO storage.buckets (id, name, public)
VALUES ('promenades-photos', 'promenades-photos', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "prom_photos_upload" ON storage.objects;
CREATE POLICY "prom_photos_upload" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'promenades-photos');

DROP POLICY IF EXISTS "prom_photos_select" ON storage.objects;
CREATE POLICY "prom_photos_select" ON storage.objects
  FOR SELECT USING (bucket_id = 'promenades-photos');

DROP POLICY IF EXISTS "prom_photos_delete" ON storage.objects;
CREATE POLICY "prom_photos_delete" ON storage.objects
  FOR DELETE USING (bucket_id = 'promenades-photos');
