-- Annonces chevaux : types équins (location / demi-pension / pension / valo),
-- prix + cadence, niveau recommandé, vidéos (sous selle / en liberté),
-- palmarès + indices sportifs. Toutes colonnes NULLABLES — aucun impact sur
-- l'existant. Idempotent.

ALTER TABLE public.annonces
  ADD COLUMN IF NOT EXISTS prix_unite        text,    -- 'total' | 'mois' | 'semaine' | 'convenir'
  ADD COLUMN IF NOT EXISTS niveau_recommande text,
  ADD COLUMN IF NOT EXISTS video_monte_url   text,
  ADD COLUMN IF NOT EXISTS video_libre_url   text,
  ADD COLUMN IF NOT EXISTS palmares          text,
  ADD COLUMN IF NOT EXISTS indice_iso        integer,
  ADD COLUMN IF NOT EXISTS indice_idr        integer,
  ADD COLUMN IF NOT EXISTS indice_icc        integer;
