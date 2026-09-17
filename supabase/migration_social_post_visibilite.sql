-- Visibilité des posts Pets Social : 'public' (tout le monde, défaut) ou
-- 'amis' (PetFriends acceptés uniquement — cf. table petfriends). Filtrage
-- fait côté appli (comme le reste de Pets Social), pas de RLS dédiée : le
-- projet n'utilise pas l'auth Supabase native (Firebase Auth + client
-- anon), donc auth.uid() n'est pas exploitable ici — même pattern que le
-- reste des tables sociales (lecture publique, filtrage applicatif).

ALTER TABLE public.posts_socialmedia
  ADD COLUMN IF NOT EXISTS visibilite TEXT NOT NULL DEFAULT 'public'
    CHECK (visibilite IN ('public', 'amis'));

CREATE INDEX IF NOT EXISTS idx_posts_socialmedia_visibilite
  ON public.posts_socialmedia (visibilite);
