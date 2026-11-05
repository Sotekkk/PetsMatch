-- Élevage : RDV vétérinaire à venir, validé depuis l'agenda (05/11/2026).
-- Un RDV pris hors PetsMatch (cabinet non inscrit) est une tâche d'agenda
-- (taches_elevage) : elle reste affichée tant qu'elle n'est pas faite, se reporte,
-- et concerne un ou plusieurs animaux (animaux_ids : toute une portée).
--   • rdv_veto_cabinet (obligatoire) marque la tâche comme RDV vétérinaire.
--   • Passage à « fait » : une visite au carnet par animal, avec le cabinet ; le
--     registre sanitaire suit tout seul (trg_registre_depuis_visite). Écrit en base
--     pour tous les écrans (agenda, Mes tâches, employé) et toutes les versions.
--     Identifiant fixe par tâche et animal : pas de doublon.
--   • Date de la visite = date de la tâche (le récapitulatif y met la date réelle),
--     jamais dans le futur.
--   • Retour à « à faire » : visites de cette tâche retirées (registre compris).
--   • Tâche supprimée : les visites déjà créées restent au carnet.
-- Idempotent.

BEGIN;

ALTER TABLE public.taches_elevage ADD COLUMN IF NOT EXISTS rdv_veto_cabinet text;
ALTER TABLE public.taches_elevage ADD COLUMN IF NOT EXISTS rdv_veto_motif text;

ALTER TABLE public.taches_elevage DROP CONSTRAINT IF EXISTS taches_rdv_veto_cabinet_chk;
ALTER TABLE public.taches_elevage ADD CONSTRAINT taches_rdv_veto_cabinet_chk
  CHECK (rdv_veto_cabinet IS NULL OR trim(rdv_veto_cabinet) <> '');

CREATE OR REPLACE FUNCTION public.pm_rdv_veto_tache_statut()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_animal text;
  v_prefixe text := 'rdvv_' || NEW.id::text || '_';
BEGIN
  IF NEW.statut = 'fait' THEN
    FOREACH v_animal IN ARRAY COALESCE(NULLIF(NEW.animaux_ids, '{}'), ARRAY[NEW.animal_id]) LOOP
      CONTINUE WHEN NULLIF(trim(COALESCE(v_animal, '')), '') IS NULL;
      INSERT INTO visites (id, animal_id, motif, veterinaire, date, notes, source)
      VALUES (v_prefixe || v_animal, v_animal,
        COALESCE(NULLIF(trim(COALESCE(NEW.rdv_veto_motif, '')), ''), 'Consultation'),
        trim(NEW.rdv_veto_cabinet),
        LEAST(NEW.date, (now() AT TIME ZONE 'Europe/Paris')::date),
        NULLIF(trim(COALESCE(NEW.notes, '')), ''),
        'owner')
      ON CONFLICT (id) DO NOTHING;
    END LOOP;
  ELSIF OLD.statut = 'fait' THEN
    DELETE FROM visites WHERE starts_with(id, v_prefixe);
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_rdv_veto_tache_statut ON public.taches_elevage;
CREATE TRIGGER trg_rdv_veto_tache_statut AFTER UPDATE OF statut ON public.taches_elevage
  FOR EACH ROW
  WHEN (NEW.rdv_veto_cabinet IS NOT NULL AND OLD.statut IS DISTINCT FROM NEW.statut)
  EXECUTE FUNCTION public.pm_rdv_veto_tache_statut();

COMMIT;
