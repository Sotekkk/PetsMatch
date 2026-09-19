-- Forum communauté : permet de joindre une photo OU une vidéo à un sujet ou
-- une réponse (même pattern que pension_updates : un seul média par
-- publication, photo_url/video_url mutuellement exclusifs côté appli).

ALTER TABLE public.forum_sujets   ADD COLUMN IF NOT EXISTS photo_url TEXT;
ALTER TABLE public.forum_sujets   ADD COLUMN IF NOT EXISTS video_url TEXT;
ALTER TABLE public.forum_reponses ADD COLUMN IF NOT EXISTS photo_url TEXT;
ALTER TABLE public.forum_reponses ADD COLUMN IF NOT EXISTS video_url TEXT;
