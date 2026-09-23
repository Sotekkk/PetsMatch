-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 32/N : Pets Social (fil principal)
--   posts_socialmedia, post_comments, post_likes, post_favorites,
--   post_reports, follows, posts (table historique inutilisée)
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- posts_socialmedia est LE fil Pets Social (posts_service / social_feed_page)
-- — jamais touché jusqu'ici, donc entièrement ouvert : n'importe qui pouvait
-- modifier/supprimer la publication de n'importe qui.
--
-- Point important : la visibilité "amis" (mutuels via `follows`) n'était
-- filtrée QUE côté client (social_feed_page.dart _friendProfileIds) — un
-- post "amis" était donc déjà envoyé sur le fil à n'importe quel visiteur,
-- simplement masqué dans l'UI. Reproduit ici en SQL (fonction
-- can_view_social_post, SECURITY DEFINER) pour que ce filtrage devienne
-- une vraie règle serveur, pas juste un affichage : lecture publique si
-- visibilite = 'public'/NULL, sinon auteur ou ami mutuel uniquement.
-- post_comments/post_likes réutilisent cette même fonction (un commentaire
-- ou un like sur un post "amis" ne doit pas fuiter le post lui-même).
--
-- post_favorites : liste personnelle ("mes posts enregistrés"), jamais lue
-- pour un autre uid dans le code — privée au propriétaire.
--
-- post_reports : même faille que signalements (vague 25/N) — verrouillé au
-- signaleur + admin.
--
-- follows : qui suit qui est déjà affiché publiquement (liste
-- followers/following d'un profil) — lecture publique conservée, écriture
-- réservée au follower lui-même (créer/supprimer SON propre suivi).
--
-- posts : table historique (migration Firestore → Supabase, cf.
-- supabase_migration_page.dart), plus lue par aucune fonctionnalité en
-- production actuelle — verrouillée par sécurité (owner via uid_eleveur +
-- cogérant), sans impact fonctionnel connu.
--
-- ⚠️ À TESTER après exécution :
--   1. Le fil Pets Social (publier, liker, commenter, favoris) fonctionne
--      normalement pour un compte connecté.
--   2. Un post "amis" reste visible pour l'auteur et un ami mutuel, invisible
--      pour un tiers/non connecté.
--   3. Suivre/ne plus suivre quelqu'un fonctionne ; la liste
--      followers/following d'un profil reste visible publiquement.
--   4. Signaler un post fonctionne toujours.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── Fonction : un post "amis" est-il visible pour p_uid ? ─────────────────
CREATE OR REPLACE FUNCTION public.can_view_social_post(p_post_id UUID, p_uid TEXT)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM posts_socialmedia p
    WHERE p.id = p_post_id
      AND (
        p.visibilite IS DISTINCT FROM 'amis'
        OR p.uid = p_uid
        OR (
          p_uid IS NOT NULL AND p.author_profile_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM user_profiles up
            WHERE up.uid = p_uid
              AND EXISTS (
                SELECT 1 FROM follows f1
                WHERE f1.follower_profile_id = up.id AND f1.following_profile_id = p.author_profile_id
              )
              AND EXISTS (
                SELECT 1 FROM follows f2
                WHERE f2.follower_profile_id = p.author_profile_id AND f2.following_profile_id = up.id
              )
          )
        )
      )
  );
$$;
GRANT EXECUTE ON FUNCTION public.can_view_social_post(UUID, TEXT) TO anon, authenticated;

-- ── posts_socialmedia ───────────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE posts_socialmedia ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'posts_socialmedia'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.posts_socialmedia', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "posts_socialmedia_select" ON posts_socialmedia
  FOR SELECT USING (public.can_view_social_post(id, (auth.jwt() ->> 'sub')));
CREATE POLICY "posts_socialmedia_insert" ON posts_socialmedia
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = uid);
CREATE POLICY "posts_socialmedia_update" ON posts_socialmedia
  FOR UPDATE USING ((auth.jwt() ->> 'sub') = uid) WITH CHECK ((auth.jwt() ->> 'sub') = uid);
CREATE POLICY "posts_socialmedia_delete" ON posts_socialmedia
  FOR DELETE USING ((auth.jwt() ->> 'sub') = uid);

-- ── post_comments (lecture = visibilité du post parent, écriture = self) ──
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE post_comments ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'post_comments'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.post_comments', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "post_comments_select" ON post_comments
  FOR SELECT USING (public.can_view_social_post(post_id, (auth.jwt() ->> 'sub')));
CREATE POLICY "post_comments_insert" ON post_comments
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = uid
    AND public.can_view_social_post(post_id, (auth.jwt() ->> 'sub'))
  );
CREATE POLICY "post_comments_update" ON post_comments
  FOR UPDATE USING ((auth.jwt() ->> 'sub') = uid) WITH CHECK ((auth.jwt() ->> 'sub') = uid);
CREATE POLICY "post_comments_delete" ON post_comments
  FOR DELETE USING ((auth.jwt() ->> 'sub') = uid);

-- ── post_likes (lecture = visibilité du post parent, écriture = self) ─────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE post_likes ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'post_likes'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.post_likes', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "post_likes_select" ON post_likes
  FOR SELECT USING (public.can_view_social_post(post_id, (auth.jwt() ->> 'sub')));
CREATE POLICY "post_likes_write" ON post_likes
  FOR ALL USING ((auth.jwt() ->> 'sub') = uid) WITH CHECK ((auth.jwt() ->> 'sub') = uid);

-- ── post_favorites (privé au propriétaire, post_id est TEXT ici) ──────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE post_favorites ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'post_favorites'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.post_favorites', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "post_favorites_owner" ON post_favorites
  FOR ALL USING ((auth.jwt() ->> 'sub') = uid) WITH CHECK ((auth.jwt() ->> 'sub') = uid);

-- ── post_reports (comme signalements, vague 25/N) ──────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE post_reports ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'post_reports'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.post_reports', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "post_reports_select" ON post_reports
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = reporter_uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );
CREATE POLICY "post_reports_insert" ON post_reports
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = reporter_uid);
CREATE POLICY "post_reports_update" ON post_reports
  FOR UPDATE USING (public.is_admin_uid((auth.jwt() ->> 'sub')))
  WITH CHECK (public.is_admin_uid((auth.jwt() ->> 'sub')));
CREATE POLICY "post_reports_delete" ON post_reports
  FOR DELETE USING (public.is_admin_uid((auth.jwt() ->> 'sub')));

-- ── follows (lecture publique, écriture par le follower lui-même) ─────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE follows ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'follows'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.follows', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "follows_select" ON follows FOR SELECT USING (true);
CREATE POLICY "follows_insert" ON follows
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = follower_uid);
CREATE POLICY "follows_delete" ON follows
  FOR DELETE USING ((auth.jwt() ->> 'sub') = follower_uid);

-- ── posts (table historique, plus utilisée) ────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  IF to_regclass('public.posts') IS NULL THEN RETURN; END IF;
  ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'posts'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.posts', pol.policyname);
  END LOOP;
  EXECUTE $p$
    CREATE POLICY "posts_owner_or_cogerant" ON posts
      FOR ALL USING (
        (auth.jwt() ->> 'sub') = uid_eleveur
        OR EXISTS (
          SELECT 1 FROM elevage_cogerants c
          WHERE c.uid_gerant = posts.uid_eleveur
            AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
        )
      )
      WITH CHECK (
        (auth.jwt() ->> 'sub') = uid_eleveur
        OR EXISTS (
          SELECT 1 FROM elevage_cogerants c
          WHERE c.uid_gerant = posts.uid_eleveur
            AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
        )
      )
  $p$;
END $$;

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('posts_socialmedia','post_comments','post_likes','post_favorites','post_reports','follows','posts')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('posts_socialmedia','post_comments','post_likes','post_favorites','post_reports','follows','posts')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- ALTER TABLE posts_socialmedia DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE post_comments DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE post_likes DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE post_favorites DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE post_reports DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE follows DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE posts DISABLE ROW LEVEL SECURITY;
