-- RPC get_admin_stats() — retourne les stats globales sans être bloqué par RLS
-- Utilisé par le panel admin web et Flutter pour afficher les compteurs du Dashboard

CREATE OR REPLACE FUNCTION get_admin_stats()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'total_animaux',              (SELECT COUNT(*) FROM animaux),
    'particuliers',               (SELECT COUNT(*) FROM animaux WHERE uid_eleveur IS NULL),
    'eleveurs',                   (SELECT COUNT(*) FROM animaux WHERE uid_eleveur IS NOT NULL),
    'par_espece', (
      SELECT COALESCE(jsonb_object_agg(esp, cnt), '{}')
      FROM (
        SELECT COALESCE(espece, 'autre') AS esp, COUNT(*) AS cnt
        FROM animaux
        GROUP BY espece
      ) s
    ),
    'top_races', (
      SELECT COALESCE(jsonb_agg(r ORDER BY r->>'cnt' DESC), '[]')
      FROM (
        SELECT jsonb_build_object('race', race, 'cnt', COUNT(*)) AS r
        FROM animaux
        WHERE race IS NOT NULL AND race <> ''
        GROUP BY race
        ORDER BY COUNT(*) DESC
        LIMIT 5
      ) t
    ),
    'total_profils',                  (SELECT COUNT(*) FROM users),
    'total_annonces',                 (SELECT COUNT(*) FROM annonces),
    'annonces_actives',               (SELECT COUNT(*) FROM annonces WHERE statut = 'active'),
    'total_signalements_en_attente',  (SELECT COUNT(*) FROM signalements WHERE statut = 'en_attente'),
    'profils_en_attente',             (SELECT COUNT(*) FROM users WHERE statut_pro = 'en_attente')
  ) INTO result;
  RETURN result;
END;
$$;

-- Autoriser tous les utilisateurs authentifiés à appeler cette fonction
-- (la guard admin est faite côté app, pas ici)
GRANT EXECUTE ON FUNCTION get_admin_stats() TO authenticated;
