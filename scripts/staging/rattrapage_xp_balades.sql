-- Balades ludiques — rattrapage des XP.
-- Les parcours terminés avant la correction (05/10/2026) n'avaient rapporté
-- aucun XP (enregistrement en échec), et les rejeux augmentaient à tort le
-- nombre de parcours terminés. Recalcul par profil à partir des
-- progressions : XP = somme des récompenses des parcours terminés au moins
-- une fois (completed_at), nombre = parcours distincts terminés.
-- Une seule requête : compatible avec l'éditeur SQL Supabase.

WITH calc AS (
  SELECT pr.joueur_profile_id AS profile_id,
         min(pr.joueur_uid)    AS user_uid,
         sum(coalesce(b.xp_recompense, 0)) AS xp_total,
         count(DISTINCT pr.balade_id)      AS nb
  FROM balades_ludiques_progressions pr
  JOIN balades_ludiques b ON b.id = pr.balade_id
  WHERE pr.completed_at IS NOT NULL AND pr.joueur_profile_id IS NOT NULL
  GROUP BY pr.joueur_profile_id
)
INSERT INTO joueurs_xp (profile_id, user_uid, xp_total, nb_parcours_completes, updated_at)
SELECT profile_id, user_uid, xp_total, nb, now() FROM calc
ON CONFLICT (profile_id) DO UPDATE
  SET xp_total = EXCLUDED.xp_total,
      nb_parcours_completes = EXCLUDED.nb_parcours_completes,
      updated_at = now()
RETURNING profile_id, xp_total, nb_parcours_completes;
