-- Forum communauté : relie chaque sujet/réponse au PROFIL (user_profiles.id)
-- de son auteur, pas seulement à son uid Firebase — nécessaire pour afficher
-- l'identité Pets Social (avatar, nom, badge pro) et pouvoir ouvrir le
-- profil de l'auteur depuis le forum. Même pattern que
-- posts_socialmedia.author_profile_id.

ALTER TABLE public.forum_sujets ADD COLUMN IF NOT EXISTS auteur_profile_id uuid;
ALTER TABLE public.forum_reponses ADD COLUMN IF NOT EXISTS auteur_profile_id uuid;

CREATE INDEX IF NOT EXISTS idx_forum_sujets_auteur_profile ON public.forum_sujets (auteur_profile_id);
CREATE INDEX IF NOT EXISTS idx_forum_reponses_auteur_profile ON public.forum_reponses (auteur_profile_id);
