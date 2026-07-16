-- ============================================================
-- PetsMatch — Galerie de livraison (photographe animalier)
-- 3 tables : albums_photo (un album par prestation livrée), album_photos
-- (photos de l'album, upload via storage_helper.dart bucket media),
-- album_partage (lien public par token, calqué sur partage_animal —
-- même mécanisme : token auto-généré, expire_at, actif).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS albums_photo (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid           TEXT NOT NULL,
  pro_profile_id    UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
  rdv_id            UUID REFERENCES rdv(id) ON DELETE SET NULL,
  client_uid        TEXT,
  client_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  titre             TEXT NOT NULL DEFAULT 'Séance photo',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_albums_photo_pro ON albums_photo(pro_uid, pro_profile_id);
CREATE INDEX IF NOT EXISTS idx_albums_photo_client ON albums_photo(client_uid, client_profile_id);
CREATE INDEX IF NOT EXISTS idx_albums_photo_rdv ON albums_photo(rdv_id);

ALTER TABLE albums_photo ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "albums_photo_all" ON albums_photo;
CREATE POLICY "albums_photo_all" ON albums_photo FOR ALL USING (true);

CREATE TABLE IF NOT EXISTS album_photos (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  album_id   UUID NOT NULL REFERENCES albums_photo(id) ON DELETE CASCADE,
  photo_url  TEXT NOT NULL,
  favori     BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_album_photos_album ON album_photos(album_id);

ALTER TABLE album_photos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "album_photos_all" ON album_photos;
CREATE POLICY "album_photos_all" ON album_photos FOR ALL USING (true);

-- Partage public par token — même mécanisme que partage_animal (lecture
-- seule, sans connexion requise, expire_at + actif).
CREATE TABLE IF NOT EXISTS album_partage (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  album_id   UUID NOT NULL REFERENCES albums_photo(id) ON DELETE CASCADE,
  token      TEXT UNIQUE DEFAULT gen_random_uuid()::TEXT,
  expire_at  TIMESTAMPTZ NOT NULL,
  actif      BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_album_partage_album ON album_partage(album_id);
CREATE INDEX IF NOT EXISTS idx_album_partage_token ON album_partage(token);

ALTER TABLE album_partage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "album_partage_all" ON album_partage;
CREATE POLICY "album_partage_all" ON album_partage FOR ALL USING (true);
