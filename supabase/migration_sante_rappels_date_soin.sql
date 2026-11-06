-- Rappels santé : seul un soin SAISI PLUS TARD fait d'une ligne une « saisie
-- d'historique » (06/11/2026).
-- Complète migration_sante_rappels_vaccin_type.sql. Avant : une ligne était
-- traitée comme de l'historique dès qu'une autre ligne du même produit avait
-- une date de rappel plus lointaine, même si cette autre ligne était un soin
-- PLUS ANCIEN (Tokyo : « virbac » du 19/05 avec rappel en 2027). Le soin
-- renouvelé ensuite ne retirait alors ni les anciennes notifications, ni
-- l'ancien rappel d'agenda, ni la tâche du jour.
-- Règle désormais (identique à functions/sante.js dejaRemplace et à l'accueil
-- éleveur) : une autre ligne a un soin plus récent, ou le même jour avec un
-- rappel plus lointain.
-- Seule la fonction change (le reste est repris tel quel). Pas de réparation :
-- ne touche que les prochaines saisies. Idempotent.

BEGIN;

CREATE OR REPLACE FUNCTION public.pm_sante_rappel_a_jour()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_col TEXT := CASE TG_TABLE_NAME WHEN 'vaccinations' THEN 'vaccin' ELSE 'produit' END;
  v_label TEXT := CASE TG_TABLE_NAME WHEN 'vaccinations' THEN 'Vaccin' WHEN 'vermifuges' THEN 'Vermifuge' ELSE 'Antiparasitaire' END;
  v_nom TEXT := trim(COALESCE(to_jsonb(NEW) ->> v_col, ''));
  v_noms TEXT[];
  v_type TEXT;
  v_plus_recent BOOLEAN;
BEGIN
  IF v_nom = '' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND NEW.date IS NOT DISTINCT FROM OLD.date AND NEW.date_rappel IS NOT DISTINCT FROM OLD.date_rappel THEN
    RETURN NEW;
  END IF;
  -- Toujours en retard : les relances continuent.
  IF NEW.date_rappel IS NOT NULL AND NEW.date_rappel < (now() AT TIME ZONE 'Europe/Paris')::date THEN
    RETURN NEW;
  END IF;

  IF TG_TABLE_NAME = 'vaccinations' THEN
    v_type := pm_type_vaccin(to_jsonb(NEW) ->> 'categorie', v_nom);
    SELECT array_agg(DISTINCT trim(x.vaccin)) INTO v_noms FROM vaccinations x
     WHERE x.animal_id = NEW.animal_id AND trim(COALESCE(x.vaccin, '')) <> ''
       AND (pm_type_vaccin(x.categorie, x.vaccin) = v_type OR lower(trim(x.vaccin)) = lower(v_nom));
    -- Saisie d'historique : un soin plus récent existe pour ce type.
    SELECT EXISTS (SELECT 1 FROM vaccinations x WHERE x.animal_id = NEW.animal_id AND x.id::text <> NEW.id::text
        AND (pm_type_vaccin(x.categorie, x.vaccin) = v_type OR lower(trim(x.vaccin)) = lower(v_nom))
        AND (x.date > NEW.date OR (x.date = NEW.date AND x.date_rappel > NEW.date_rappel))) INTO v_plus_recent;
  ELSE
    v_noms := ARRAY[v_nom];
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I x WHERE x.animal_id = $1 AND x.id::text <> $2
        AND lower(trim(x.produit)) = lower($3) AND (x.date > $4 OR (x.date = $4 AND x.date_rappel > $5)))', TG_TABLE_NAME)
      INTO v_plus_recent USING NEW.animal_id, NEW.id::text, v_nom, NEW.date, NEW.date_rappel;
  END IF;
  IF v_plus_recent THEN RETURN NEW; END IF;

  DELETE FROM notifications n
   WHERE n.type = 'sante' AND n.data ->> 'table' = TG_TABLE_NAME AND n.data ->> 'animalId' = NEW.animal_id::text
     AND jsonb_array_length(COALESCE(NULLIF(n.data -> 'animalIds', 'null'::jsonb), '[]'::jsonb)) <= 1
     AND EXISTS (SELECT 1 FROM unnest(v_noms) x WHERE pm_notif_sante_produit(n.body, x));

  DELETE FROM agenda_events e
   WHERE e.animal_id = NEW.animal_id::text AND e.type = 'medication'
     AND EXISTS (SELECT 1 FROM unnest(v_noms) x WHERE pm_titre_rappel_sante(e.titre, lower(v_label), x))
     AND (e.date_debut AT TIME ZONE 'Europe/Paris')::date IS DISTINCT FROM NEW.date_rappel;

  -- Tâche du jour J : le soin est fait (elle reste visible, cochée).
  UPDATE taches_elevage t SET statut = 'fait'
   WHERE t.animal_id = NEW.animal_id::text AND t.statut = 'a_faire'
     AND t.titre ILIKE '%' || v_label || ' — %'
     AND EXISTS (SELECT 1 FROM unnest(v_noms) x WHERE lower(COALESCE(t.notes, '')) = lower(x)
                   OR starts_with(lower(COALESCE(t.notes, '')), lower(x) || ' — '));

  RETURN NEW;
END;
$function$;

COMMIT;
