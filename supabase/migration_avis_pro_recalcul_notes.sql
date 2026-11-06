-- ══════════════════════════════════════════════════════════════════════════
-- Annuaire : note moyenne + nombre d'avis à jour sur chaque profil pro
-- (06/11/2026)
-- ══════════════════════════════════════════════════════════════════════════
-- L'annuaire (site + appli) affiche user_profiles.note_moyenne / nb_avis,
-- tenus à jour par le trigger trg_update_pro_rating (SECURITY DEFINER depuis
-- migration_rls_triggers_definer.sql). Avant ce correctif, le trigger tournait
-- avec les droits de l'auteur de l'avis et la mise à jour du profil pro
-- pouvait échouer en silence : recalcul unique de tous les profils.
-- Rejouable sans risque.
-- ══════════════════════════════════════════════════════════════════════════

BEGIN;

UPDATE user_profiles up SET
  nb_avis      = s.nb,
  note_moyenne = s.moy
FROM (
  SELECT p.id,
         count(a.id)                       AS nb,
         coalesce(round(avg(a.note), 2), 0) AS moy
    FROM user_profiles p
    LEFT JOIN avis_pro a ON a.pro_profile_id = p.id
   GROUP BY p.id
) s
WHERE s.id = up.id
  AND (coalesce(up.nb_avis, -1) <> s.nb OR coalesce(up.note_moyenne, -1) <> s.moy);

COMMIT;

-- Vérification : profils pro avec avis.
-- SELECT id, nom, note_moyenne, nb_avis FROM user_profiles WHERE nb_avis > 0 ORDER BY nb_avis DESC;
