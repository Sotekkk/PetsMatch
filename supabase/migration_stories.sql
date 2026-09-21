-- ═══════════════════════════════════════════════════════════════════════════
-- Pets Social — Stories éphémères (24h) avec musique libre de droits
--
-- • story_music_tracks : bibliothèque maison uniquement (pas d'import libre
--   côté utilisateur, donc aucune détection de droits nécessaire — chaque
--   morceau est ajouté à la main depuis /admin, avec sa licence vérifiée
--   avant mise en ligne). Sources recommandées : Pixabay Music
--   (pixabay.com/music, licence "Content License" — gratuite, aucune
--   attribution requise, la plus simple) ou Incompetech/Kevin MacLeod
--   (CC-BY — attribution obligatoire, renseigner `attribution`).
-- • stories : une story = une publication éphémère (photo ou vidéo, 24h),
--   avec musique optionnelle piochée dans story_music_tracks.
-- • story_views : qui a vu quoi, pour l'écran « Vu par » et ne pas compter
--   deux fois le même spectateur.
-- • Purge : `expires_at` sert de filtre client (jamais affichée après), et
--   une Cloud Function planifiée supprime réellement les lignes + fichiers
--   Storage après 24h pour limiter le volume utilisé (cf.
--   functions/stories_cleanup.js).
--
-- À exécuter dans Supabase SQL Editor (une seule fois).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Bibliothèque musicale ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.story_music_tracks (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  titre          text NOT NULL,
  artiste        text,
  url_audio      text NOT NULL,
  duree_secondes integer,
  cover_url      text,
  licence        text NOT NULL DEFAULT 'CC0',   -- 'CC0' | 'CC-BY' | 'libre_verifie'
  attribution    text,                          -- texte à afficher si licence l'exige (CC-BY)
  actif          boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_story_music_tracks_actif
  ON public.story_music_tracks (actif) WHERE actif = true;

-- ── Stories ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.stories (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  uid               text NOT NULL,
  author_profile_id uuid NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  media_url         text NOT NULL,
  media_type        text NOT NULL DEFAULT 'photo',  -- 'photo' | 'video'
  duree_secondes    integer,                         -- durée de la vidéo, pour la barre de progression
  music_track_id    uuid REFERENCES public.story_music_tracks(id) ON DELETE SET NULL,
  legende           text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  expires_at        timestamptz NOT NULL DEFAULT (now() + interval '24 hours')
);

CREATE INDEX IF NOT EXISTS idx_stories_author_profile ON public.stories (author_profile_id);
CREATE INDEX IF NOT EXISTS idx_stories_expires_at      ON public.stories (expires_at);

-- ── Vues ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.story_views (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id          uuid NOT NULL REFERENCES public.stories(id) ON DELETE CASCADE,
  viewer_uid        text NOT NULL,
  viewer_profile_id uuid REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  viewed_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (story_id, viewer_profile_id)
);

CREATE INDEX IF NOT EXISTS idx_story_views_story ON public.story_views (story_id);

-- ── Storage : media des stories (photos/vidéos) ─────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('stories', 'stories', true)
ON CONFLICT (id) DO NOTHING;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='stories_public_read'
  ) THEN
    CREATE POLICY "stories_public_read"
      ON storage.objects FOR SELECT
      USING (bucket_id = 'stories');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='stories_anon_insert'
  ) THEN
    CREATE POLICY "stories_anon_insert"
      ON storage.objects FOR INSERT
      WITH CHECK (bucket_id = 'stories');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='stories_anon_delete'
  ) THEN
    CREATE POLICY "stories_anon_delete"
      ON storage.objects FOR DELETE
      USING (bucket_id = 'stories');
  END IF;
END $$;

-- ── Storage : bibliothèque musicale (gérée depuis /admin uniquement) ───────
INSERT INTO storage.buckets (id, name, public)
VALUES ('story_music', 'story_music', true)
ON CONFLICT (id) DO NOTHING;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='story_music_public_read'
  ) THEN
    CREATE POLICY "story_music_public_read"
      ON storage.objects FOR SELECT
      USING (bucket_id = 'story_music');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='story_music_anon_insert'
  ) THEN
    CREATE POLICY "story_music_anon_insert"
      ON storage.objects FOR INSERT
      WITH CHECK (bucket_id = 'story_music');
  END IF;
END $$;
