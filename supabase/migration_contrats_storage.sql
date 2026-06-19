-- Bucket public pour les contrats signés
INSERT INTO storage.buckets (id, name, public)
VALUES ('contrats', 'contrats', true)
ON CONFLICT (id) DO NOTHING;

-- Lecture publique (pour partager le lien)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='contrats_public_read'
  ) THEN
    CREATE POLICY "contrats_public_read"
      ON storage.objects FOR SELECT
      USING (bucket_id = 'contrats');
  END IF;
END $$;

-- Écriture via anon key (depuis le navigateur)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='contrats_anon_insert'
  ) THEN
    CREATE POLICY "contrats_anon_insert"
      ON storage.objects FOR INSERT
      WITH CHECK (bucket_id = 'contrats');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='contrats_anon_update'
  ) THEN
    CREATE POLICY "contrats_anon_update"
      ON storage.objects FOR UPDATE
      USING (bucket_id = 'contrats');
  END IF;
END $$;
