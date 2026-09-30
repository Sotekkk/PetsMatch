-- ════════════════════════════════════════════════════════════════════════
-- RLS : données privées encore lisibles par tous (groupe 5c, partie 1).
--
-- Avant (lecture USING (true), et quelques insertions trop larges) :
--   • activity_log : historique d'activité (balades, distances, XP) de
--     tout le monde ; insertion possible AU NOM de n'importe qui (uid non
--     nul suffisait) → XP gonflable ;
--   • conversation_reports : signalements de conversations (motif,
--     détails) lisibles par tous ; signalement possible sans compte ;
--   • annonces_stats_daily / annonces_views_geo / animaux_portee_stats :
--     statistiques de toutes les annonces (+ route /api/annonces/stats
--     sans contrôle, corrigée dans le même commit) ;
--   • evenements_inscrits : qui est inscrit à quel événement ;
--   • promenades_messages : discussion d'une promenade lisible par tous ;
--   • groupes PRIVÉS : publications, commentaires et likes lisibles par
--     tous (seul le groupe lui-même est visible de tous, pour qu'on puisse
--     le trouver et demander à le rejoindre).
--
-- Après :
--   • activity_log : ses propres lignes (policy activity_log_owner) ;
--     insertion à son nom uniquement ;
--   • conversation_reports : l'auteur du signalement + admins (policy
--     existante) ; signaler = être connecté, en son nom ;
--   • stats d'annonces : propriétaire / cogérant de l'annonce (policies
--     *_write existantes) ; incréments via RPC SECURITY DEFINER (inchangés) ;
--   • evenements_inscrits : ses inscriptions + le créateur de l'événement ;
--   • promenades_messages : organisateur et participants acceptés ;
--   • groupes privés : contenus réservés aux membres actifs ; groupes
--     publics : inchangés.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── activity_log ───────────────────────────────────────────────────────
DROP POLICY IF EXISTS activity_log_select ON public.activity_log;
DROP POLICY IF EXISTS activity_log_insert ON public.activity_log;
CREATE POLICY activity_log_insert ON public.activity_log
  FOR INSERT TO anon, authenticated
  WITH CHECK ((auth.jwt() ->> 'sub') = uid);

-- ── conversation_reports ───────────────────────────────────────────────
DROP POLICY IF EXISTS allow_read_reports ON public.conversation_reports;
DROP POLICY IF EXISTS allow_insert_reports ON public.conversation_reports;
-- conversation_reports_select (auteur + admin), _insert (en son nom),
-- _update / _delete (admin) conservées.

-- ── statistiques d'annonces ────────────────────────────────────────────
DROP POLICY IF EXISTS annonces_stats_daily_select ON public.annonces_stats_daily;
DROP POLICY IF EXISTS annonces_views_geo_select ON public.annonces_views_geo;
DROP POLICY IF EXISTS animaux_portee_stats_select ON public.animaux_portee_stats;
-- *_write (ALL : propriétaire / cogérant de l'annonce) couvrent la lecture.

-- ── evenements_inscrits ────────────────────────────────────────────────
DROP POLICY IF EXISTS evenements_inscrits_select ON public.evenements_inscrits;
CREATE POLICY evenements_inscrits_select ON public.evenements_inscrits
  FOR SELECT TO anon, authenticated
  USING (
    (auth.jwt() ->> 'sub') = user_uid
    OR EXISTS (SELECT 1 FROM public.evenements e
               WHERE e.id = evenements_inscrits.evenement_id
                 AND e.createur_uid = (auth.jwt() ->> 'sub'))
  );

-- ── promenades_messages ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.pm_membre_promenade(p_promenade_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (auth.jwt() ->> 'sub') IS NOT NULL AND (
    EXISTS (SELECT 1 FROM promenades p
            WHERE p.id = p_promenade_id AND p.organisateur_uid = (auth.jwt() ->> 'sub'))
    OR EXISTS (SELECT 1 FROM promenades_participants pp
               WHERE pp.promenade_id = p_promenade_id
                 AND pp.user_uid = (auth.jwt() ->> 'sub') AND pp.statut = 'accepte')
  );
$$;
GRANT EXECUTE ON FUNCTION public.pm_membre_promenade(uuid) TO anon, authenticated;

DROP POLICY IF EXISTS promenades_messages_select ON public.promenades_messages;
CREATE POLICY promenades_messages_select ON public.promenades_messages
  FOR SELECT TO anon, authenticated
  USING (public.pm_membre_promenade(promenade_id));
DROP POLICY IF EXISTS promenades_messages_insert ON public.promenades_messages;
CREATE POLICY promenades_messages_insert ON public.promenades_messages
  FOR INSERT TO anon, authenticated
  WITH CHECK ((auth.jwt() ->> 'sub') = user_uid AND public.pm_membre_promenade(promenade_id));

-- ── groupes privés : contenus réservés aux membres ─────────────────────
CREATE OR REPLACE FUNCTION public.pm_groupe_lisible(p_groupe_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM groupes g
    WHERE g.id = p_groupe_id
      AND (
        NOT coalesce(g.prive, false)
        OR g.createur_uid = (auth.jwt() ->> 'sub')
        OR EXISTS (SELECT 1 FROM groupes_membres gm
                   WHERE gm.groupe_id = g.id AND gm.user_uid = (auth.jwt() ->> 'sub')
                     AND gm.statut = 'active')
        OR public.is_admin_uid(auth.jwt() ->> 'sub')
      )
  );
$$;
GRANT EXECUTE ON FUNCTION public.pm_groupe_lisible(uuid) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.pm_post_groupe_lisible(p_post_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM groupe_posts p
                 WHERE p.id = p_post_id AND public.pm_groupe_lisible(p.groupe_id));
$$;
GRANT EXECUTE ON FUNCTION public.pm_post_groupe_lisible(uuid) TO anon, authenticated;

DROP POLICY IF EXISTS groupe_posts_select ON public.groupe_posts;
CREATE POLICY groupe_posts_select ON public.groupe_posts
  FOR SELECT TO anon, authenticated
  USING (public.pm_groupe_lisible(groupe_id));

DROP POLICY IF EXISTS groupe_post_commentaires_select ON public.groupe_post_commentaires;
CREATE POLICY groupe_post_commentaires_select ON public.groupe_post_commentaires
  FOR SELECT TO anon, authenticated
  USING (public.pm_post_groupe_lisible(post_id));

DROP POLICY IF EXISTS groupe_post_likes_select ON public.groupe_post_likes;
CREATE POLICY groupe_post_likes_select ON public.groupe_post_likes
  FOR SELECT TO anon, authenticated
  USING (public.pm_post_groupe_lisible(post_id));

DROP POLICY IF EXISTS groupe_commentaire_likes_select ON public.groupe_commentaire_likes;
CREATE POLICY groupe_commentaire_likes_select ON public.groupe_commentaire_likes
  FOR SELECT TO anon, authenticated
  USING (EXISTS (SELECT 1 FROM public.groupe_post_commentaires c
                 WHERE c.id = groupe_commentaire_likes.comment_id));

COMMIT;
