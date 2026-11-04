-- Rappels santé : vaccin refait sous une autre marque, même type (04/11/2026).
-- Complète migration_sante_rappels_a_jour.sql : même règle que les rappels
-- (functions/sante.js, typeVaccin) — un vaccin renouvelé remplace les rappels
-- de son type (catégorie, ou nom si la catégorie est vide / « Autre »), quelle
-- que soit la marque : Rabisin en 2026 remplace Nobivac Rage de 2025.
-- Le produit est reconnu exactement dans les textes (« Effitix pour Luna »,
-- « Rappel demain : Effitix pour Luna. ») et non plus comme un bout de phrase :
-- « DAPPi » ne retire pas « DAPPi Lmulti » d'un autre type.
-- Réparation de l'existant dans sauv_rappels_sante_20261104. Idempotent.

BEGIN;

CREATE OR REPLACE FUNCTION public.pm_type_vaccin(p_categorie text, p_vaccin text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN lower(trim(COALESCE(p_categorie, ''))) NOT IN ('', 'autre')
    THEN lower(trim(p_categorie)) ELSE lower(trim(COALESCE(p_vaccin, ''))) END;
$function$;

-- Le produit [p_nom] est-il celui de ce texte de notification ?
CREATE OR REPLACE FUNCTION public.pm_notif_sante_produit(p_body text, p_nom text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT starts_with(lower(COALESCE(p_body, '')), lower(p_nom) || ' pour ')
      OR position(' : ' || lower(p_nom) || ' pour ' IN lower(COALESCE(p_body, ''))) > 0;
$function$;

-- Le titre d'événement est-il « Rappel <libellé> — <nom> », seul ou « (Luna) »,
-- et non un rappel groupé « (Luna, Milo) » ?
CREATE OR REPLACE FUNCTION public.pm_titre_rappel_sante(p_titre text, p_libelle text, p_nom text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT starts_with(lower(p_titre), lower('Rappel ' || p_libelle || ' — ' || p_nom))
     AND (length(p_titre) = length('Rappel ' || p_libelle || ' — ' || p_nom)
          OR (substr(p_titre, length('Rappel ' || p_libelle || ' — ' || p_nom) + 1) LIKE ' (%'
              AND position(', ' IN substr(p_titre, length('Rappel ' || p_libelle || ' — ' || p_nom) + 1)) = 0));
$function$;

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
    -- Saisie d'historique : une ligne plus récente existe pour ce type.
    SELECT EXISTS (SELECT 1 FROM vaccinations x WHERE x.animal_id = NEW.animal_id AND x.id::text <> NEW.id::text
        AND (pm_type_vaccin(x.categorie, x.vaccin) = v_type OR lower(trim(x.vaccin)) = lower(v_nom))
        AND (x.date > NEW.date OR x.date_rappel > NEW.date_rappel)) INTO v_plus_recent;
  ELSE
    v_noms := ARRAY[v_nom];
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I x WHERE x.animal_id = $1 AND x.id::text <> $2
        AND lower(trim(x.produit)) = lower($3) AND (x.date > $4 OR x.date_rappel > $5))', TG_TABLE_NAME)
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

-- ── Réparation : vaccins renouvelés sous une autre marque ─────────────────────
CREATE TEMP TABLE _vaccins_a_jour ON COMMIT DROP AS
  SELECT d.animal_id, d.type_vaccin, d.date_rappel, n.nom
    FROM (
      SELECT DISTINCT ON (animal_id, pm_type_vaccin(categorie, vaccin)) animal_id, pm_type_vaccin(categorie, vaccin) AS type_vaccin, date_rappel
        FROM vaccinations WHERE trim(COALESCE(vaccin, '')) <> ''
       ORDER BY animal_id, pm_type_vaccin(categorie, vaccin), date_rappel DESC NULLS LAST, date DESC NULLS LAST
    ) d
    JOIN (
      SELECT DISTINCT animal_id, pm_type_vaccin(categorie, vaccin) AS type_vaccin, trim(vaccin) AS nom
        FROM vaccinations WHERE trim(COALESCE(vaccin, '')) <> ''
    ) n ON n.animal_id = d.animal_id AND n.type_vaccin = d.type_vaccin
   WHERE d.date_rappel >= (now() AT TIME ZONE 'Europe/Paris')::date;

WITH suppr AS (
  DELETE FROM notifications n USING _vaccins_a_jour s
   WHERE n.type = 'sante' AND n.data ->> 'table' = 'vaccinations' AND n.data ->> 'animalId' = s.animal_id::text
     AND jsonb_array_length(COALESCE(NULLIF(n.data -> 'animalIds', 'null'::jsonb), '[]'::jsonb)) <= 1
     AND pm_notif_sante_produit(n.body, s.nom)
     -- Rappel à venir (J-7, J-1, J-0 de la date actuelle) : gardé.
     AND (n.data ->> 'overdue' = 'true' OR n.created_at::date < s.date_rappel - 7)
  RETURNING n.*
)
INSERT INTO public.sauv_rappels_sante_20261104 (source, ligne) SELECT 'notifications', to_jsonb(suppr) FROM suppr;

WITH suppr AS (
  DELETE FROM agenda_events e USING _vaccins_a_jour s
   WHERE e.animal_id = s.animal_id::text AND e.type = 'medication'
     AND pm_titre_rappel_sante(e.titre, 'vaccin', s.nom)
     AND (e.date_debut AT TIME ZONE 'Europe/Paris')::date IS DISTINCT FROM s.date_rappel
  RETURNING e.*
)
INSERT INTO public.sauv_rappels_sante_20261104 (source, ligne) SELECT 'agenda_events', to_jsonb(suppr) FROM suppr;

UPDATE taches_elevage t SET statut = 'fait' FROM _vaccins_a_jour s
 WHERE t.animal_id = s.animal_id::text AND t.statut = 'a_faire' AND t.date < s.date_rappel
   AND t.titre ILIKE '%Vaccin — %'
   AND (lower(COALESCE(t.notes, '')) = lower(s.nom) OR starts_with(lower(COALESCE(t.notes, '')), lower(s.nom) || ' — '));

COMMIT;
