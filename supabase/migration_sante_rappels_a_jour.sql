-- Rappels santé (vaccin, vermifuge, antiparasitaire) : plus d'empilement (04/11/2026).
-- Cas Luna / Effitix : 47 notifications « en retard » non lues pour une seule
-- fiche, et les événements d'agenda s'ajoutaient à chaque rappel.
--   • Renouvellement (nouvelle ligne au carnet, ou date de rappel déplacée) :
--     les notifications de ce produit pour cet animal, l'ancien événement
--     d'agenda sont retirés et la tâche « à faire » passe en « fait ».
--   • Rien n'est retiré tant que le soin reste en retard (les relances continuent
--     jusqu'à ce que l'utilisateur renouvelle ou coupe) ni si la ligne saisie
--     est plus ancienne qu'une autre (saisie d'historique).
--   • Rappels groupés sur plusieurs animaux : non touchés (ils concernent aussi
--     les autres animaux).
-- Une seule ligne « en retard » par soin à l'avenir : functions/sante.js.
-- Réparation de l'existant, lignes retirées gardées dans sauv_rappels_sante_20261104.
-- Idempotent.

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
  v_prefixe TEXT;
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
  -- Saisie d'historique : une ligne plus récente existe pour ce produit.
  EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I x WHERE x.animal_id = $1 AND x.id::text <> $2
      AND lower(trim(x.%I)) = lower($3) AND (x.date > $4 OR x.date_rappel > $5))', TG_TABLE_NAME, v_col)
    INTO v_plus_recent USING NEW.animal_id, NEW.id::text, v_nom, NEW.date, NEW.date_rappel;
  IF v_plus_recent THEN RETURN NEW; END IF;

  DELETE FROM notifications n
   WHERE n.type = 'sante' AND n.data ->> 'table' = TG_TABLE_NAME AND n.data ->> 'animalId' = NEW.animal_id::text
     AND jsonb_array_length(COALESCE(NULLIF(n.data -> 'animalIds', 'null'::jsonb), '[]'::jsonb)) <= 1
     AND position(lower(v_nom) IN lower(COALESCE(n.body, ''))) > 0;

  -- Titres : « Rappel antiparasitaire — Effitix » suivi de « (Luna) » (groupe : « (Luna, Milo) »).
  v_prefixe := 'Rappel ' || lower(v_label) || ' — ' || v_nom;
  DELETE FROM agenda_events e
   WHERE e.animal_id = NEW.animal_id::text AND e.type = 'medication'
     AND lower(left(e.titre, length(v_prefixe))) = lower(v_prefixe)
     AND (length(e.titre) = length(v_prefixe)
          OR (substr(e.titre, length(v_prefixe) + 1) LIKE ' (%' AND position(', ' IN substr(e.titre, length(v_prefixe) + 1)) = 0))
     AND (e.date_debut AT TIME ZONE 'Europe/Paris')::date IS DISTINCT FROM NEW.date_rappel;

  -- Tâche du jour J : le soin est fait (elle reste visible, cochée).
  UPDATE taches_elevage t SET statut = 'fait'
   WHERE t.animal_id = NEW.animal_id::text AND t.statut = 'a_faire'
     AND t.titre ILIKE '%' || v_label || ' — %'
     AND position(lower(v_nom) IN lower(COALESCE(t.notes, ''))) > 0;

  RETURN NEW;
END;
$function$;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['vaccinations', 'vermifuges', 'antiparasitaires'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_sante_rappel_a_jour ON public.%I', t);
    EXECUTE format('CREATE TRIGGER trg_sante_rappel_a_jour AFTER INSERT OR UPDATE OF date, date_rappel ON public.%I
      FOR EACH ROW EXECUTE FUNCTION public.pm_sante_rappel_a_jour()', t);
  END LOOP;
END $$;

-- ── Réparation de l'existant ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.sauv_rappels_sante_20261104 (
  source TEXT NOT NULL, ligne JSONB NOT NULL, retire_le TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.sauv_rappels_sante_20261104 ENABLE ROW LEVEL SECURITY; -- aucune policy : clé de service seulement

-- 1) Notifications « en retard » du même soin : seule la plus récente reste.
WITH suppr AS (
  DELETE FROM notifications n USING (
    SELECT id, row_number() OVER (PARTITION BY uid, data ->> 'table', data ->> 'recordId' ORDER BY created_at DESC, id DESC) AS rang
      FROM notifications
     WHERE type = 'sante' AND data ->> 'overdue' = 'true' AND data ->> 'recordId' IS NOT NULL
  ) d
  WHERE n.id = d.id AND d.rang > 1
  RETURNING n.*
)
INSERT INTO public.sauv_rappels_sante_20261104 (source, ligne) SELECT 'notifications', to_jsonb(suppr) FROM suppr;

-- 2) Soins renouvelés (dernière ligne du produit à jour) : notifications,
--    événements et tâches périmés, comme le fait le déclencheur.
DO $$
DECLARE
  t TEXT; c TEXT; l TEXT; dernieres TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['vaccinations', 'vermifuges', 'antiparasitaires'] LOOP
    c := CASE t WHEN 'vaccinations' THEN 'vaccin' ELSE 'produit' END;
    l := CASE t WHEN 'vaccinations' THEN 'Vaccin' WHEN 'vermifuges' THEN 'Vermifuge' ELSE 'Antiparasitaire' END;
    dernieres := format($q$
      SELECT DISTINCT ON (animal_id, lower(trim(%1$I))) animal_id, trim(%1$I) AS nom, date_rappel
        FROM public.%2$I WHERE trim(COALESCE(%1$I, '')) <> ''
       ORDER BY animal_id, lower(trim(%1$I)), date_rappel DESC NULLS LAST, date DESC NULLS LAST
    $q$, c, t);
    EXECUTE format($q$
      WITH suppr AS (
        DELETE FROM notifications n USING (%1$s) s
         WHERE n.type = 'sante' AND n.data ->> 'table' = %2$L AND n.data ->> 'animalId' = s.animal_id::text
           AND (s.date_rappel IS NULL OR s.date_rappel >= (now() AT TIME ZONE 'Europe/Paris')::date)
           AND jsonb_array_length(COALESCE(NULLIF(n.data -> 'animalIds', 'null'::jsonb), '[]'::jsonb)) <= 1
           AND position(lower(s.nom) IN lower(COALESCE(n.body, ''))) > 0
           -- Rappel à venir (J-7, J-1, J-0 de la date actuelle) : gardé.
           AND (n.data ->> 'overdue' = 'true' OR n.created_at::date < COALESCE(s.date_rappel, current_date) - 7)
        RETURNING n.*
      )
      INSERT INTO public.sauv_rappels_sante_20261104 (source, ligne) SELECT 'notifications', to_jsonb(suppr) FROM suppr
    $q$, dernieres, t);
    EXECUTE format($q$
      WITH suppr AS (
        DELETE FROM agenda_events e USING (%1$s) s
         WHERE e.animal_id = s.animal_id::text AND e.type = 'medication'
           AND (s.date_rappel IS NULL OR s.date_rappel >= (now() AT TIME ZONE 'Europe/Paris')::date)
           AND lower(left(e.titre, length('Rappel ' || %2$L || ' — ' || s.nom))) = lower('Rappel ' || %2$L || ' — ' || s.nom)
           AND (length(e.titre) = length('Rappel ' || %2$L || ' — ' || s.nom)
                OR (substr(e.titre, length('Rappel ' || %2$L || ' — ' || s.nom) + 1) LIKE ' (%%'
                    AND position(', ' IN substr(e.titre, length('Rappel ' || %2$L || ' — ' || s.nom) + 1)) = 0))
           AND (e.date_debut AT TIME ZONE 'Europe/Paris')::date IS DISTINCT FROM s.date_rappel
        RETURNING e.*
      )
      INSERT INTO public.sauv_rappels_sante_20261104 (source, ligne) SELECT 'agenda_events', to_jsonb(suppr) FROM suppr
    $q$, dernieres, lower(l));
    EXECUTE format($q$
      UPDATE taches_elevage x SET statut = 'fait' FROM (%1$s) s
       WHERE x.animal_id = s.animal_id::text AND x.statut = 'a_faire'
         AND (s.date_rappel IS NOT NULL AND s.date_rappel >= (now() AT TIME ZONE 'Europe/Paris')::date AND x.date < s.date_rappel)
         AND x.titre ILIKE '%%' || %2$L || ' — %%'
         AND position(lower(s.nom) IN lower(COALESCE(x.notes, ''))) > 0
    $q$, dernieres, l);
  END LOOP;
END $$;

-- 3) Événements identiques (même compte, animal, titre, jour) : un seul reste.
WITH suppr AS (
  DELETE FROM agenda_events e USING (
    SELECT id, row_number() OVER (PARTITION BY uid, animal_id, titre, (date_debut AT TIME ZONE 'Europe/Paris')::date ORDER BY id DESC) AS rang
      FROM agenda_events
     WHERE type = 'medication' AND titre LIKE 'Rappel %'
  ) d
  WHERE e.id = d.id AND d.rang > 1
  RETURNING e.*
)
INSERT INTO public.sauv_rappels_sante_20261104 (source, ligne) SELECT 'agenda_events', to_jsonb(suppr) FROM suppr;

COMMIT;
