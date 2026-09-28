-- ═══════════════════════════════════════════════════════════════════════════
-- Pets Social — Stories publicitaires (régie interne)
--
-- Injectées côté client dans le flux de stories (story_ring.dart) toutes les
-- N stories cumulées vues, comme Instagram/Snapchat. Pas de SDK tiers : les
-- annonceurs sont gérés à la main depuis /admin (table ci-dessous), chaque
-- pub étant rendue par StoryViewerPage exactement comme une story normale
-- (mêmes barres de progression, même plein écran), avec un CTA en bas au
-- lieu du bouton like.
--
-- À exécuter dans Supabase SQL Editor (une seule fois).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.story_ads (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  annonceur_nom     text NOT NULL,
  annonceur_logo_url text,
  media_url         text NOT NULL,
  media_type        text NOT NULL DEFAULT 'photo',   -- 'photo' | 'video'
  duree_secondes    integer,                          -- durée vidéo/photo custom (sinon 6s par défaut)
  cta_label         text NOT NULL DEFAULT 'En savoir plus',
  lien_url          text,                             -- lien externe (http/https) ouvert au tap sur le CTA
  actif             boolean NOT NULL DEFAULT true,
  date_debut        timestamptz NOT NULL DEFAULT now(),
  date_fin          timestamptz,                      -- NULL = pas de date de fin
  poids             integer NOT NULL DEFAULT 1,        -- pondération de sélection si plusieurs pubs actives
  impressions       bigint NOT NULL DEFAULT 0,
  clics             bigint NOT NULL DEFAULT 0,
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_story_ads_actif ON public.story_ads (actif) WHERE actif = true;

-- ── Storage : media des stories pub (même bucket public que les stories) ────
INSERT INTO storage.buckets (id, name, public)
VALUES ('stories', 'stories', true)
ON CONFLICT (id) DO NOTHING;

-- ── Compteurs atomiques (évite les races impressions/clics concurrents) ──────
CREATE OR REPLACE FUNCTION public.increment_story_ad_impressions(ad_id uuid)
RETURNS void AS $$
  UPDATE public.story_ads SET impressions = impressions + 1 WHERE id = ad_id;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION public.increment_story_ad_clics(ad_id uuid)
RETURNS void AS $$
  UPDATE public.story_ads SET clics = clics + 1 WHERE id = ad_id;
$$ LANGUAGE sql;
