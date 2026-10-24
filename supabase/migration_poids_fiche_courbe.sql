-- ════════════════════════════════════════════════════════════════════════
-- Poids : la fiche et la courbe ne font plus qu'un.
--
-- Règle : animaux.poids = le DERNIER point de la courbe (table poids).
--   • saisir / modifier le poids sur la fiche (création comprise) → point de
--     la courbe daté du jour (mis à jour s'il existe déjà un point ce jour-là,
--     sinon ajouté) ;
--   • ajouter / modifier / supprimer un point de la courbe → la fiche reprend
--     la valeur du dernier point (aucun point = poids vide).
-- Avant : un chien créé avec son poids avait une courbe vide, et un poids
-- ajouté à la courbe ne changeait pas la fiche (6 fiches en désaccord).
--
-- Fait par la base : appli, site, pension, compte rendu véto… tous suivent.
-- Idempotent. Rattrapage des données existantes en fin de fichier.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

-- NUMERIC(6,3) plafonnait à 999 kg : un cheval de 1 000 kg aurait fait
-- échouer l'enregistrement de sa fiche (le point de courbe est créé avec).
ALTER TABLE public.poids ALTER COLUMN valeur TYPE NUMERIC(8,3);
-- Identifiant par défaut : la fiche association insérait une pesée sans id
-- (refusée, colonne id TEXT sans valeur par défaut).
ALTER TABLE public.poids ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;

-- Fiche → courbe.
CREATE OR REPLACE FUNCTION public.pm_poids_fiche_vers_courbe()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id text;
BEGIN
  IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;  -- mise à jour venue de la courbe
  IF current_setting('pm.sync_poids', true) = 'off' THEN RETURN NEW; END IF;  -- rattrapage
  IF NEW.poids IS NULL THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND NEW.poids IS NOT DISTINCT FROM OLD.poids THEN RETURN NEW; END IF;
  SELECT id INTO v_id FROM poids
   WHERE animal_id = NEW.id AND date = current_date
   ORDER BY created_at DESC LIMIT 1;
  IF v_id IS NOT NULL THEN
    UPDATE poids SET valeur = NEW.poids WHERE id = v_id AND valeur IS DISTINCT FROM NEW.poids;
  ELSE
    INSERT INTO poids (id, animal_id, valeur, date, notes)
    VALUES (gen_random_uuid()::text, NEW.id, NEW.poids, current_date, 'Poids de la fiche');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_poids_fiche_vers_courbe ON public.animaux;
CREATE TRIGGER trg_poids_fiche_vers_courbe
  AFTER INSERT OR UPDATE OF poids ON public.animaux
  FOR EACH ROW EXECUTE FUNCTION public.pm_poids_fiche_vers_courbe();

-- Courbe → fiche.
CREATE OR REPLACE FUNCTION public.pm_poids_courbe_vers_fiche()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_animal text := coalesce(NEW.animal_id, OLD.animal_id);
  v_dernier numeric;
BEGIN
  IF pg_trigger_depth() > 1 THEN RETURN NULL; END IF;  -- point écrit depuis la fiche
  IF current_setting('pm.sync_poids', true) = 'off' THEN RETURN NULL; END IF;  -- rattrapage
  SELECT valeur INTO v_dernier FROM poids
   WHERE animal_id = v_animal AND valeur IS NOT NULL
   ORDER BY date DESC NULLS LAST, created_at DESC
   LIMIT 1;
  UPDATE animaux SET poids = v_dernier
   WHERE id = v_animal AND poids IS DISTINCT FROM v_dernier;
  -- Point déplacé vers un autre animal (rare) : l'ancien suit aussi.
  IF TG_OP = 'UPDATE' AND OLD.animal_id IS DISTINCT FROM NEW.animal_id THEN
    UPDATE animaux a SET poids = (
      SELECT valeur FROM poids WHERE animal_id = OLD.animal_id AND valeur IS NOT NULL
       ORDER BY date DESC NULLS LAST, created_at DESC LIMIT 1)
     WHERE a.id = OLD.animal_id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_poids_courbe_vers_fiche ON public.poids;
CREATE TRIGGER trg_poids_courbe_vers_fiche
  AFTER INSERT OR UPDATE OR DELETE ON public.poids
  FOR EACH ROW EXECUTE FUNCTION public.pm_poids_courbe_vers_fiche();

-- ── Rattrapage (triggers suspendus le temps de la transaction) ─────────────
SET LOCAL pm.sync_poids = 'off';
-- 1. Fiche avec un poids mais courbe vide : premier point, daté de la création.
INSERT INTO poids (id, animal_id, valeur, date, notes)
SELECT gen_random_uuid()::text, a.id, a.poids, coalesce(a.created_at::date, current_date), 'Poids de la fiche'
  FROM animaux a
 WHERE a.poids IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM poids p WHERE p.animal_id = a.id);

-- 2. Fiche ≠ dernier point de la courbe : la courbe fait foi.
UPDATE animaux a SET poids = d.valeur
  FROM (SELECT DISTINCT ON (animal_id) animal_id, valeur
          FROM poids WHERE valeur IS NOT NULL
         ORDER BY animal_id, date DESC NULLS LAST, created_at DESC) d
 WHERE d.animal_id = a.id AND a.poids IS DISTINCT FROM d.valeur;

COMMIT;
