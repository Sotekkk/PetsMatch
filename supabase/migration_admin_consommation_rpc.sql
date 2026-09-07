-- RPC admin_consommation_stats() — stats de consommation par uid ET par profil.
-- SECURITY DEFINER, AUCUN GRANT public : appelée uniquement via la clé service
-- role dans website/src/app/api/admin/stats/route.ts (garde admin dans la route).

CREATE OR REPLACE FUNCTION admin_consommation_stats()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  by_uid     jsonb;
  by_profile jsonb;
BEGIN
  ------------------------------------------------------------------ par profil
  WITH prof AS (
    SELECT p.id, p.uid, p.profile_type, p.is_main,
           COALESCE(NULLIF(TRIM(p.nom), ''),
                    NULLIF(TRIM(COALESCE(p.firstname,'') || ' ' || COALESCE(p.lastname,'')), ''),
                    'Profil') AS nom,
           p.plan_code, p.is_premium, p.created_at
    FROM user_profiles p
  ),
  an_owned AS (   -- animaux rattachés à ce profil (lien actif)
    SELECT ap.profile_id_proprio AS pid, COUNT(*) AS n
    FROM animaux_proprietes ap
    WHERE ap.profile_id_proprio IS NOT NULL AND ap.date_fin IS NULL
    GROUP BY ap.profile_id_proprio
  ),
  annonces_p AS (
    SELECT a.profile_id AS pid,
           COUNT(*) AS n_total,
           COUNT(*) FILTER (WHERE a.statut = 'disponible') AS n_actives,
           COALESCE(SUM(a.vues), 0) AS vues,
           COUNT(*) FILTER (WHERE a.boost_until IS NOT NULL AND a.boost_until > now()) AS boosts
    FROM annonces a WHERE a.profile_id IS NOT NULL
    GROUP BY a.profile_id
  ),
  msg_p AS (
    SELECT sender_profile_id AS pid, COUNT(*) AS n
    FROM messages WHERE sender_profile_id IS NOT NULL GROUP BY sender_profile_id
  ),
  posts_p AS (
    SELECT author_profile_id AS pid, COUNT(*) AS n
    FROM posts_socialmedia WHERE author_profile_id IS NOT NULL GROUP BY author_profile_id
  ),
  rdv_p AS (
    SELECT pid, COUNT(*) AS n FROM (
      SELECT pro_profile_id AS pid FROM rdv WHERE pro_profile_id IS NOT NULL
      UNION ALL
      SELECT client_profile_id AS pid FROM rdv WHERE client_profile_id IS NOT NULL
    ) s GROUP BY pid
  )
  -- NB : balades_ludiques_progressions n'a pas de joueur_profile_id en base →
  -- les stats balades sont uniquement au niveau uid (voir plus bas).
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'profile_id', prof.id,
    'uid', prof.uid,
    'profile_type', prof.profile_type,
    'is_main', prof.is_main,
    'nom', prof.nom,
    'plan_code', prof.plan_code,
    'is_premium', prof.is_premium,
    'created_at', prof.created_at,
    'animaux', COALESCE(an_owned.n, 0),
    'annonces_total', COALESCE(annonces_p.n_total, 0),
    'annonces_actives', COALESCE(annonces_p.n_actives, 0),
    'annonces_vues', COALESCE(annonces_p.vues, 0),
    'boosts_actifs', COALESCE(annonces_p.boosts, 0),
    'messages', COALESCE(msg_p.n, 0),
    'posts', COALESCE(posts_p.n, 0),
    'rdv', COALESCE(rdv_p.n, 0),
    'balade_parcours', 0,
    'balade_termines', 0,
    'balade_points', 0,
    'balade_km', 0
  ) ORDER BY prof.uid, prof.is_main DESC), '[]'::jsonb)
  INTO by_profile
  FROM prof
  LEFT JOIN an_owned    ON an_owned.pid    = prof.id
  LEFT JOIN annonces_p  ON annonces_p.pid  = prof.id
  LEFT JOIN msg_p       ON msg_p.pid       = prof.id
  LEFT JOIN posts_p     ON posts_p.pid     = prof.id
  LEFT JOIN rdv_p       ON rdv_p.pid       = prof.id;

  ------------------------------------------------------------------ par uid
  WITH u AS (
    SELECT DISTINCT uid FROM user_profiles WHERE uid IS NOT NULL
  ),
  ident AS (
    SELECT p.uid,
           MIN(p.created_at) AS inscrit_le,
           jsonb_agg(DISTINCT p.profile_type) AS types,
           (ARRAY_AGG(p.plan_code ORDER BY p.is_main DESC))[1] AS plan_principal,
           bool_or(p.is_premium) AS premium
    FROM user_profiles p GROUP BY p.uid
  ),
  usr AS (
    SELECT uid, email, last_active FROM users
  ),
  an_u AS (
    SELECT uid, COUNT(*) AS n FROM (
      SELECT DISTINCT ap.animal_id, ap.uid_proprio AS uid
      FROM animaux_proprietes ap WHERE ap.uid_proprio IS NOT NULL AND ap.date_fin IS NULL
      UNION
      SELECT DISTINCT a.id, COALESCE(a.uid_eleveur, a.uid_proprietaire) AS uid
      FROM animaux a WHERE COALESCE(a.uid_eleveur, a.uid_proprietaire) IS NOT NULL
    ) s WHERE uid IS NOT NULL GROUP BY uid
  ),
  annonces_u AS (
    SELECT uid_eleveur AS uid,
           COUNT(*) AS n_total,
           COUNT(*) FILTER (WHERE statut = 'disponible') AS n_actives,
           COALESCE(SUM(vues), 0) AS vues,
           COALESCE(SUM(COALESCE(array_length(photos, 1), 0)), 0) AS photos,
           COUNT(*) FILTER (WHERE boost_until IS NOT NULL AND boost_until > now()) AS boosts
    FROM annonces WHERE uid_eleveur IS NOT NULL GROUP BY uid_eleveur
  ),
  media_u AS (
    SELECT uid,
           COUNT(*) FILTER (WHERE photo_url IS NOT NULL AND photo_url <> '') AS n
    FROM (
      SELECT COALESCE(a.uid_eleveur, a.uid_proprietaire) AS uid, a.photo_url
      FROM animaux a
    ) s WHERE uid IS NOT NULL GROUP BY uid
  ),
  msg_u AS (
    SELECT sender_id AS uid, COUNT(*) AS n
    FROM messages WHERE sender_id IS NOT NULL GROUP BY sender_id
  ),
  conv_u AS (
    SELECT uid, COUNT(*) AS n FROM (
      SELECT jsonb_array_elements_text(participants) AS uid
      FROM conversations
      WHERE participants IS NOT NULL AND jsonb_typeof(participants) = 'array'
    ) s GROUP BY uid
  ),
  posts_u AS (
    SELECT uid, COUNT(*) AS n FROM posts_socialmedia WHERE uid IS NOT NULL GROUP BY uid
  ),
  rdv_u AS (
    SELECT uid, COUNT(*) AS n FROM (
      SELECT pro_uid AS uid FROM rdv WHERE pro_uid IS NOT NULL
      UNION ALL
      SELECT client_uid AS uid FROM rdv WHERE client_uid IS NOT NULL
    ) s GROUP BY uid
  ),
  balade_u AS (
    SELECT pr.joueur_uid AS uid,
           COUNT(*) AS parcours,
           COUNT(*) FILTER (WHERE pr.statut = 'termine') AS termines,
           COALESCE(SUM(b.distance_km) FILTER (WHERE pr.statut = 'termine'), 0) AS km
    FROM balades_ludiques_progressions pr
    LEFT JOIN balades_ludiques b ON b.id = pr.balade_id
    WHERE pr.joueur_uid IS NOT NULL GROUP BY pr.joueur_uid
  ),
  abo_u AS (
    SELECT ab.uid, jsonb_agg(jsonb_build_object(
      'profil_type', ab.profil_type, 'plan_code', ab.plan_code, 'periodicite', ab.periodicite,
      'manuel', ab.stripe_subscription_id IS NULL, 'date_fin', ab.date_fin
    )) AS abos
    FROM abonnements ab WHERE ab.statut = 'actif' GROUP BY ab.uid
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'uid', u.uid,
    'email', usr.email,
    'inscrit_le', ident.inscrit_le,
    'derniere_activite', usr.last_active,
    'types', COALESCE(ident.types, '[]'::jsonb),
    'plan_principal', ident.plan_principal,
    'premium', COALESCE(ident.premium, false),
    'abos_actifs', COALESCE(abo_u.abos, '[]'::jsonb),
    'animaux', COALESCE(an_u.n, 0),
    'annonces_total', COALESCE(annonces_u.n_total, 0),
    'annonces_actives', COALESCE(annonces_u.n_actives, 0),
    'annonces_vues', COALESCE(annonces_u.vues, 0),
    'boosts_actifs', COALESCE(annonces_u.boosts, 0),
    'photos_estimees', COALESCE(annonces_u.photos, 0) + COALESCE(media_u.n, 0),
    'messages', COALESCE(msg_u.n, 0),
    'conversations', COALESCE(conv_u.n, 0),
    'posts', COALESCE(posts_u.n, 0),
    'rdv', COALESCE(rdv_u.n, 0),
    'balade_parcours', COALESCE(balade_u.parcours, 0),
    'balade_termines', COALESCE(balade_u.termines, 0),
    'balade_km', ROUND(COALESCE(balade_u.km, 0)::numeric, 1)
  ) ORDER BY (COALESCE(annonces_u.vues, 0) + COALESCE(an_u.n, 0) * 10) DESC), '[]'::jsonb)
  INTO by_uid
  FROM u
  LEFT JOIN ident      ON ident.uid      = u.uid
  LEFT JOIN usr        ON usr.uid        = u.uid
  LEFT JOIN an_u       ON an_u.uid       = u.uid
  LEFT JOIN annonces_u ON annonces_u.uid = u.uid
  LEFT JOIN media_u    ON media_u.uid    = u.uid
  LEFT JOIN msg_u      ON msg_u.uid      = u.uid
  LEFT JOIN conv_u     ON conv_u.uid     = u.uid
  LEFT JOIN posts_u    ON posts_u.uid    = u.uid
  LEFT JOIN rdv_u      ON rdv_u.uid      = u.uid
  LEFT JOIN balade_u   ON balade_u.uid   = u.uid
  LEFT JOIN abo_u      ON abo_u.uid      = u.uid;

  RETURN jsonb_build_object('by_uid', by_uid, 'by_profile', by_profile, 'generated_at', now());
END;
$$;

REVOKE ALL ON FUNCTION admin_consommation_stats() FROM public;
REVOKE ALL ON FUNCTION admin_consommation_stats() FROM authenticated;
REVOKE ALL ON FUNCTION admin_consommation_stats() FROM anon;
GRANT EXECUTE ON FUNCTION admin_consommation_stats() TO service_role;
