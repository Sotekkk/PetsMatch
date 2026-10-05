-- Loup (Refuge de la Marne) : passé « adopté » le 06/07/2026 par un ancien
-- chemin qui ne changeait QUE le statut (menu de statut du site / fiche
-- chenil, corrigés depuis) → aucune sortie au registre, propriété jamais
-- clôturée. Rattrapage : sortie inscrite au registre du profil association,
-- date de sortie, propriété clôturée.
BEGIN;

UPDATE animaux SET date_sortie = '2026-07-06'
WHERE id = 'animal_xoRHVSob5uTWm3sbl6lKWFuIgKF2_1783351993608' AND date_sortie IS NULL;

INSERT INTO registre_mouvements (animal_id, uid_eleveur, eleveur_profile_id, type, date_mouvement, motif)
SELECT 'animal_xoRHVSob5uTWm3sbl6lKWFuIgKF2_1783351993608', 'xoRHVSob5uTWm3sbl6lKWFuIgKF2',
       'ee6e5849-dc1f-4999-bcfd-1c6843fd6944', 'sortie', '2026-07-06', 'cession'
WHERE NOT EXISTS (
  SELECT 1 FROM registre_mouvements
  WHERE animal_id = 'animal_xoRHVSob5uTWm3sbl6lKWFuIgKF2_1783351993608' AND type = 'sortie');

UPDATE animaux_proprietes SET date_fin = '2026-07-06'
WHERE animal_id = 'animal_xoRHVSob5uTWm3sbl6lKWFuIgKF2_1783351993608'
  AND uid_proprio = 'xoRHVSob5uTWm3sbl6lKWFuIgKF2' AND date_fin IS NULL;

SELECT type, date_mouvement, motif FROM registre_mouvements
WHERE animal_id = 'animal_xoRHVSob5uTWm3sbl6lKWFuIgKF2_1783351993608';

COMMIT;
