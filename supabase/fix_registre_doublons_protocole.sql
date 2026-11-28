-- Registre sanitaire : lignes en double après validation d'une tâche de
-- protocole (vermifuge, antiparasitaire, vaccin, traitement). La validation
-- écrivait une ligne « plan_taches » ET le carnet en faisait une seconde
-- (trigger migration_registre_depuis_carnet.sql). On garde celle du carnet.
-- Une ligne « plan_taches » n'est supprimée que si la ligne du carnet existe
-- (même animal, même acte, même registre, date de début du soin).
-- 1) Aperçu
SELECT r.id, r.animal_nom, r.type_acte, r.date_acte, r.description
FROM registre_sanitaire r
JOIN plan_taches t ON t.id::text = r.source_id
WHERE r.source_table = 'plan_taches'
  AND r.type_acte IN ('vermifuge','antiparasitaire','vaccination','traitement')
  AND EXISTS (
    SELECT 1 FROM registre_sanitaire c
    WHERE c.source_table IN ('vermifuges','antiparasitaires','vaccinations','traitements')
      AND c.animal_id = r.animal_id AND c.type_acte = r.type_acte AND c.uid_eleveur = r.uid_eleveur
      AND c.date_acte = t.date_prevue - (coalesce(t.jour_traitement, 1) - 1))
ORDER BY r.date_acte DESC;

-- 2) Suppression (mêmes conditions)
BEGIN;
DELETE FROM registre_sanitaire r
USING plan_taches t
WHERE t.id::text = r.source_id
  AND r.source_table = 'plan_taches'
  AND r.type_acte IN ('vermifuge','antiparasitaire','vaccination','traitement')
  AND EXISTS (
    SELECT 1 FROM registre_sanitaire c
    WHERE c.source_table IN ('vermifuges','antiparasitaires','vaccinations','traitements')
      AND c.animal_id = r.animal_id AND c.type_acte = r.type_acte AND c.uid_eleveur = r.uid_eleveur
      AND c.date_acte = t.date_prevue - (coalesce(t.jour_traitement, 1) - 1));
COMMIT;
