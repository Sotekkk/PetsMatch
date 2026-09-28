-- ══════════════════════════════════════════════════════════════════════════
-- Pets Social — publier un post échouait : 42501 « new row violates
-- row-level security policy for table "posts_socialmedia" »
-- ══════════════════════════════════════════════════════════════════════════
-- L'appli crée le post puis le relit dans la même requête
-- (insert(...).select('id').single() → INSERT … RETURNING). Le RETURNING
-- est soumis à la policy SELECT, qui appelait uniquement
-- can_view_social_post(id, …) (migration_rls_tighten_social_feed.sql).
-- Cette fonction STABLE recherche le post PAR SON ID dans la table : elle
-- travaille sur l'instantané pris avant l'INSERT, ne voit donc pas la ligne
-- en cours de création → false → rejet. Tout nouveau post (fil, partage de
-- balade…) était refusé.
--
-- Correctif : la policy teste d'abord les colonnes de la ligne elle-même
-- (post public / auteur = moi) — aucun besoin de relire la table — et ne
-- délègue à la fonction que le cas « amis » (posts déjà existants).
-- Règle de visibilité inchangée.
--
-- ⚠️ À TESTER après exécution :
--   1. Publier un post (texte + photo) depuis le fil → OK, visible.
--   2. Partager une balade en Post → OK.
--   3. Un post « amis » reste invisible pour un tiers non ami mutuel.
-- Si un cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "posts_socialmedia_select" ON posts_socialmedia;
CREATE POLICY "posts_socialmedia_select" ON posts_socialmedia
  FOR SELECT USING (
    visibilite IS DISTINCT FROM 'amis'
    OR uid = (auth.jwt() ->> 'sub')
    OR public.can_view_social_post(id, (auth.jwt() ->> 'sub'))
  );

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK (retour à la policy précédente) :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "posts_socialmedia_select" ON posts_socialmedia;
-- CREATE POLICY "posts_socialmedia_select" ON posts_socialmedia
--   FOR SELECT USING (public.can_view_social_post(id, (auth.jwt() ->> 'sub')));
