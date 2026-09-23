-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 28/N : stories + réseau social
--   stories, story_views, story_likes, story_music_tracks, liked_posts,
--   bloquer, conversation_reports
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- stories/story_likes/story_music_tracks/liked_posts : AUCUNE RLS jusqu'ici
-- (comme la plupart des tables jamais retouchées ce chantier). Lecture
-- publique conservée (confirmé dans story_service.dart : volontairement
-- pas de filtre "abonnements", stories visibles de tous), écriture
-- verrouillée à l'auteur.
--
-- story_views : QUI a vu MA story est une info semi-privée (comme
-- Instagram) — lecture réservée à l'auteur de la story ET au spectateur
-- lui-même (pas à un tiers), écriture réservée au spectateur.
--
-- bloquer (liste de blocages) : AUCUNE RLS — n'importe qui pouvait voir
-- qui bloque qui, et surtout SUPPRIMER le blocage d'un autre utilisateur
-- (débloquer quelqu'un à sa place, contournement de sécurité). Réservé au
-- blocker (blocker_id) uniquement, ni lecture ni écriture par un tiers.
--
-- conversation_reports : USING(true) WITH CHECK(true), même faille que
-- signalements (vague 25/N) — verrouillé pareil (auteur du signalement +
-- admin).
--
-- ⚠️ À TESTER après exécution :
--   1. Les stories (création, lecture, vues, likes, musique) fonctionnent
--      normalement pour tout le monde.
--   2. Bloquer/débloquer un utilisateur fonctionne toujours ; un AUTRE
--      utilisateur ne peut ni voir ni modifier mes blocages.
--   3. Liker un post, signaler une conversation fonctionnent toujours.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── stories (auteur = uid) ─────────────────────────────────────────────────
ALTER TABLE stories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "stories_select" ON stories FOR SELECT USING (true);
CREATE POLICY "stories_insert" ON stories FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = uid);
CREATE POLICY "stories_update" ON stories FOR UPDATE USING ((auth.jwt() ->> 'sub') = uid) WITH CHECK ((auth.jwt() ->> 'sub') = uid);
CREATE POLICY "stories_delete" ON stories FOR DELETE USING ((auth.jwt() ->> 'sub') = uid);

-- ── story_likes (self, lecture publique comme les autres likes) ───────────
ALTER TABLE story_likes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "story_likes_select" ON story_likes FOR SELECT USING (true);
CREATE POLICY "story_likes_write" ON story_likes
  FOR ALL USING ((auth.jwt() ->> 'sub') = uid) WITH CHECK ((auth.jwt() ->> 'sub') = uid);

-- ── story_views (auteur de la story + le spectateur lui-même) ─────────────
ALTER TABLE story_views ENABLE ROW LEVEL SECURITY;
CREATE POLICY "story_views_select" ON story_views
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = viewer_uid
    OR EXISTS (SELECT 1 FROM stories s WHERE s.id = story_views.story_id AND s.uid = (auth.jwt() ->> 'sub'))
  );
CREATE POLICY "story_views_insert" ON story_views
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = viewer_uid);

-- ── story_music_tracks (catalogue, lecture publique, écriture jamais côté client) ──
ALTER TABLE story_music_tracks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "story_music_tracks_select" ON story_music_tracks FOR SELECT USING (true);

-- ── liked_posts (self, lecture publique comme les autres likes) ───────────
ALTER TABLE liked_posts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "liked_posts_select" ON liked_posts FOR SELECT USING (true);
CREATE POLICY "liked_posts_write" ON liked_posts
  FOR ALL USING ((auth.jwt() ->> 'sub') = user_id) WITH CHECK ((auth.jwt() ->> 'sub') = user_id);

-- ── bloquer (privé au blocker, ni lecture ni écriture par un tiers) ───────
ALTER TABLE bloquer ENABLE ROW LEVEL SECURITY;
CREATE POLICY "bloquer_select" ON bloquer FOR SELECT USING ((auth.jwt() ->> 'sub') = blocker_id);
CREATE POLICY "bloquer_write" ON bloquer
  FOR ALL USING ((auth.jwt() ->> 'sub') = blocker_id) WITH CHECK ((auth.jwt() ->> 'sub') = blocker_id);

-- ── conversation_reports (comme signalements, vague 25/N) ─────────────────
DROP POLICY IF EXISTS "conversation_reports_all" ON conversation_reports;
CREATE POLICY "conversation_reports_select" ON conversation_reports
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = reported_by_uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );
CREATE POLICY "conversation_reports_insert" ON conversation_reports
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = reported_by_uid);
CREATE POLICY "conversation_reports_update" ON conversation_reports
  FOR UPDATE USING (public.is_admin_uid((auth.jwt() ->> 'sub')))
  WITH CHECK (public.is_admin_uid((auth.jwt() ->> 'sub')));
CREATE POLICY "conversation_reports_delete" ON conversation_reports
  FOR DELETE USING (public.is_admin_uid((auth.jwt() ->> 'sub')));

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('stories','story_views','story_likes','story_music_tracks','liked_posts','bloquer','conversation_reports')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('stories','story_views','story_likes','story_music_tracks','liked_posts','bloquer','conversation_reports')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- ALTER TABLE stories DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE story_likes DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE story_views DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE story_music_tracks DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE liked_posts DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE bloquer DISABLE ROW LEVEL SECURITY;
-- CREATE POLICY "conversation_reports_all" ON conversation_reports USING (true) WITH CHECK (true);
