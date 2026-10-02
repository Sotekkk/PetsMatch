-- ════════════════════════════════════════════════════════════════════════
-- story_ads : RLS active SANS aucune policy → personne ne lisait les pubs
-- (les stories n'en affichaient jamais) et les compteurs impressions / clics
-- (fonctions en droits utilisateur) échouaient.
-- - lecture : pubs actives dans leur période, pour tous ;
-- - compteurs : fonctions SECURITY DEFINER (seule écriture possible côté
--   appli) ;
-- - création / modification / suppression : admin via le site
--   (/api/admin/moderation, clé service) — aucune policy d'écriture.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

DROP POLICY IF EXISTS story_ads_select ON public.story_ads;
CREATE POLICY story_ads_select ON public.story_ads
  FOR SELECT TO anon, authenticated
  USING (actif AND date_debut <= now() AND (date_fin IS NULL OR date_fin > now()));

CREATE OR REPLACE FUNCTION public.increment_story_ad_impressions(ad_id uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE story_ads SET impressions = impressions + 1 WHERE id = ad_id AND actif;
$$;
CREATE OR REPLACE FUNCTION public.increment_story_ad_clics(ad_id uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE story_ads SET clics = clics + 1 WHERE id = ad_id AND actif;
$$;
GRANT EXECUTE ON FUNCTION public.increment_story_ad_impressions(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.increment_story_ad_clics(uuid) TO anon, authenticated;

COMMIT;
