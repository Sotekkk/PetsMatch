-- ═══════════════════════════════════════════════════════════════════════════
-- Pets Social — taguer un ou plusieurs animaux du compte sur une publication
--
-- • À la création d'un post, l'auteur (particulier OU pro/éleveur) peut
--   sélectionner des animaux dont il est propriétaire (`animaux_proprietes`)
--   ou éleveur (`animaux.uid_eleveur`). Les IDs sont stockés ici.
-- • Depuis la fiche d'un animal, un bouton « Publications Pets Social » ouvre
--   toutes les publications du réseau où cet animal est tagué :
--     SELECT * FROM posts_socialmedia
--     WHERE tagged_animal_ids @> ARRAY['<animal_id>']::uuid[]
--     ORDER BY created_at DESC;
--
-- À exécuter dans Supabase SQL Editor (une seule fois).
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.posts_socialmedia
  ADD COLUMN IF NOT EXISTS tagged_animal_ids uuid[] DEFAULT '{}'::uuid[];

-- Index GIN pour la requête inverse (« posts où l'animal X est tagué »).
CREATE INDEX IF NOT EXISTS idx_posts_socialmedia_tagged_animals
  ON public.posts_socialmedia USING GIN (tagged_animal_ids);
