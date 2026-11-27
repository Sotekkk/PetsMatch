-- ══════════════════════════════════════════════════════════════════════════
-- Stock bas résolu (27/11/2026)
-- ══════════════════════════════════════════════════════════════════════════
-- Une alerte « Stock bas » laisse une tâche « Commander : <article> »
-- (plan_taches, type_acte 'commande') et une notification « Stock bas ».
-- Dès que l'article n'est plus bas (quantité au-dessus du seuil, alerte
-- désactivée ou seuil retiré), quel que soit l'écran ou la personne :
--   • la tâche de commande en attente est validée (statut 'fait') ;
--   • la notification « Stock bas » non lue de l'article est marquée lue
--     (celles de péremption, même type, restent).
-- Éleveur, association, pension, vétérinaire… : même table inventaire_items.
-- ══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.pm_stock_bas_resolu()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_bas boolean := NEW.alerte_active IS TRUE AND NEW.quantite_alerte IS NOT NULL
                   AND coalesce(NEW.quantite, 0) <= NEW.quantite_alerte;
BEGIN
  IF v_bas THEN RETURN NEW; END IF;
  -- Tâche « Commander : <article> » (ancien nom aussi, si l'article a été renommé).
  UPDATE plan_taches
     SET statut = 'fait', valide_at = now(),
         notes_validation = coalesce(nullif(notes_validation, ''), 'Stock réapprovisionné')
   WHERE uid_eleveur = NEW.uid_eleveur
     AND type_acte = 'commande' AND statut = 'en_attente'
     AND label IN ('Commander : ' || NEW.nom, 'Commander : ' || OLD.nom)
     AND (NEW.eleveur_profile_id IS NULL OR eleveur_profile_id IS NULL OR eleveur_profile_id = NEW.eleveur_profile_id);
  -- Notification « Stock bas » de l'article (propriétaire et employés).
  UPDATE notifications
     SET read = true
   WHERE type = 'inventaire_alerte' AND read = false
     AND data ->> 'itemId' = NEW.id::text
     AND title ILIKE '%Stock bas%';
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_stock_bas_resolu ON public.inventaire_items;
CREATE TRIGGER trg_stock_bas_resolu
  AFTER UPDATE OF quantite, quantite_alerte, alerte_active, nom ON public.inventaire_items
  FOR EACH ROW EXECUTE FUNCTION public.pm_stock_bas_resolu();

-- Rattrapage : tâches et alertes d'articles déjà réapprovisionnés.
UPDATE plan_taches t
   SET statut = 'fait', valide_at = now(),
       notes_validation = coalesce(nullif(t.notes_validation, ''), 'Stock réapprovisionné')
  FROM inventaire_items i
 WHERE t.type_acte = 'commande' AND t.statut = 'en_attente'
   AND t.uid_eleveur = i.uid_eleveur AND t.label = 'Commander : ' || i.nom
   AND (i.eleveur_profile_id IS NULL OR t.eleveur_profile_id IS NULL OR t.eleveur_profile_id = i.eleveur_profile_id)
   AND NOT (i.alerte_active IS TRUE AND i.quantite_alerte IS NOT NULL AND coalesce(i.quantite, 0) <= i.quantite_alerte);
UPDATE notifications n
   SET read = true
  FROM inventaire_items i
 WHERE n.type = 'inventaire_alerte' AND n.read = false AND n.title ILIKE '%Stock bas%'
   AND n.data ->> 'itemId' = i.id::text
   AND NOT (i.alerte_active IS TRUE AND i.quantite_alerte IS NOT NULL AND coalesce(i.quantite, 0) <= i.quantite_alerte);

COMMIT;

-- Vérification
SELECT tgname FROM pg_trigger WHERE tgname = 'trg_stock_bas_resolu';

-- Retour arrière :
-- DROP TRIGGER IF EXISTS trg_stock_bas_resolu ON public.inventaire_items;
-- DROP FUNCTION IF EXISTS public.pm_stock_bas_resolu();
