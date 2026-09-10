-- ═══════════════════════════════════════════════════════════════════════════
-- Pets Social — tagged_animal_ids : uuid[] → text[]
-- ───────────────────────────────────────────────────────────────────────────
-- Beaucoup d'animaux ont un `id` non-UUID (format timestamp / court, hérité).
-- Un `uuid[]` rejetait le tag avec « invalid input syntax for type uuid »
-- (22P02). On passe en `text[]`, comme `annonces.animal_id`
-- (migration_annonces_animal_id_text). Idempotent.
-- ═══════════════════════════════════════════════════════════════════════════

DROP INDEX IF EXISTS public.idx_posts_socialmedia_tagged_animals;

ALTER TABLE public.posts_socialmedia
  ALTER COLUMN tagged_animal_ids DROP DEFAULT;

ALTER TABLE public.posts_socialmedia
  ALTER COLUMN tagged_animal_ids TYPE text[]
  USING COALESCE(tagged_animal_ids::text[], '{}'::text[]);

ALTER TABLE public.posts_socialmedia
  ALTER COLUMN tagged_animal_ids SET DEFAULT '{}'::text[];

-- Requête inverse (« posts où l'animal X est tagué ») :
--   SELECT * FROM posts_socialmedia
--   WHERE tagged_animal_ids @> ARRAY['<animal_id>']::text[];
CREATE INDEX IF NOT EXISTS idx_posts_socialmedia_tagged_animals
  ON public.posts_socialmedia USING GIN (tagged_animal_ids);
