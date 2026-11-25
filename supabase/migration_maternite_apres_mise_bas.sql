-- ════════════════════════════════════════════════════════════════════════
-- « Préparer la maternité — <femelle> » (functions/agenda.js, veille de la
-- mise bas prévue) : retirée dès que la mise bas est enregistrée
-- (gestations.date_naissance renseignée), quel que soit l'écran qui l'a
-- saisie (fiche animal, portée, planning — site et appli).
--
-- Remontée bêta 25/11/2026 : Natacha avait déjà validé la mise bas de Rileey,
-- la tâche est quand même apparue (le rappel ne vérifiait pas la naissance ;
-- corrigé aussi dans functions/agenda.js).
--
-- Seules les tâches encore « à faire » de CETTE gestation (date proche de la
-- mise bas prévue) sont retirées. SECURITY DEFINER : un employé qui saisit la
-- mise bas retire la tâche de l'élevage (écriture dérivée, sans entrée libre).
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.retirer_tache_maternite()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  a RECORD;
BEGIN
  IF NEW.date_naissance IS NULL OR OLD.date_naissance IS NOT NULL THEN
    RETURN NEW;
  END IF;
  SELECT id, nom, uid_eleveur INTO a FROM animaux WHERE id = NEW.animal_id;
  IF a.uid_eleveur IS NULL THEN
    RETURN NEW;
  END IF;
  DELETE FROM taches_elevage t
   WHERE t.uid_eleveur = a.uid_eleveur
     AND t.statut = 'a_faire'
     AND t.titre ILIKE '%Préparer la maternité — %'
     AND (t.animal_id::text = a.id::text
          OR (t.animal_id IS NULL AND lower(trim(t.animal_nom)) = lower(trim(a.nom))))
     AND (NEW.date_prevue IS NULL OR t.date BETWEEN NEW.date_prevue - 15 AND NEW.date_prevue + 15);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_retirer_tache_maternite ON public.gestations;
CREATE TRIGGER trg_retirer_tache_maternite
  AFTER UPDATE OF date_naissance ON public.gestations
  FOR EACH ROW EXECUTE FUNCTION public.retirer_tache_maternite();

-- Rattrapage : tâches déjà posées alors que la mise bas est enregistrée (Rileey…).
DELETE FROM taches_elevage t
 USING gestations g, animaux a
 WHERE a.id = g.animal_id
   AND g.date_naissance IS NOT NULL
   AND t.uid_eleveur = a.uid_eleveur
   AND t.statut = 'a_faire'
   AND t.titre ILIKE '%Préparer la maternité — %'
   AND (t.animal_id::text = a.id::text
        OR (t.animal_id IS NULL AND lower(trim(t.animal_nom)) = lower(trim(a.nom))))
   AND g.date_prevue IS NOT NULL
   AND t.date BETWEEN g.date_prevue - 15 AND g.date_prevue + 15;

COMMIT;
