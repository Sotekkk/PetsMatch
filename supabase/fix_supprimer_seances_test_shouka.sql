-- Suppression des séances d'essai dans l'ancien outil d'anatomie
-- (« Séances d'ostéopathie / kiné » : seances_osteo) :
--   • Shouka : 05/08/2026 et 02/08/2026
--   • Miaou  : 05/09/2026 et 05/08/2026
-- Leurs points (points_osteo.seance_id) partent avec, ON DELETE CASCADE.
-- À exécuter en deux temps : 1) vérifier l'aperçu, 2) lancer le DELETE.

-- 1) Aperçu : doit lister exactement les 4 séances d'essai
WITH cibles(nom, date_seance) AS (VALUES
  ('shouka', DATE '2026-08-05'), ('shouka', DATE '2026-08-02'),
  ('miaou',  DATE '2026-09-05'), ('miaou',  DATE '2026-08-05')
)
SELECT s.id, a.nom AS animal, s.date_seance, s.note, s.created_at,
       (SELECT count(*) FROM points_osteo p WHERE p.seance_id = s.id) AS nb_points
FROM seances_osteo s
JOIN animaux a ON a.id = s.animal_id
JOIN cibles c ON c.nom = lower(a.nom) AND c.date_seance = s.date_seance
ORDER BY a.nom, s.date_seance;

-- 2) Suppression (si l'aperçu est correct)
BEGIN;
WITH cibles(nom, date_seance) AS (VALUES
  ('shouka', DATE '2026-08-05'), ('shouka', DATE '2026-08-02'),
  ('miaou',  DATE '2026-09-05'), ('miaou',  DATE '2026-08-05')
)
DELETE FROM seances_osteo s
USING animaux a, cibles c
WHERE a.id = s.animal_id
  AND c.nom = lower(a.nom)
  AND c.date_seance = s.date_seance;
-- Vérifier le nombre de lignes supprimées (4 attendues), puis :
COMMIT;
