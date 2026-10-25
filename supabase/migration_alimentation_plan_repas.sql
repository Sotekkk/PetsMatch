-- ══════════════════════════════════════════════════════════════════════════
-- Alimentation (chien / chat) — plan par repas + contrôles serveur
-- ══════════════════════════════════════════════════════════════════════════
-- Refonte de l'onglet Alimentation (cahier des charges du 25/10/2026) :
-- chaque repas contient un ou plusieurs aliments, chacun avec sa quantité en
-- grammes. Jusqu'ici la table ne connaissait que 2 composants et un % entre
-- eux (le reste codé dans `notes`, « foin|gran|…|nbRepas|… »).
--
-- alimentations
--   plan      : { v, mode, categories, activite, poids_adulte, enregistre_le,
--                 aliments: [{id, marque, gamme, type, kcal, source}],
--                 repas: [{heure, items: [{a, g, perso, libre}]}] }
--               a = index dans aliments, g = grammes servis à ce repas,
--               libre = à volonté (foin, pâturage : pas de quantité).
--               Toutes espèces : chien / chat calculés en énergie (kcal),
--               herbivores et porcins en % du poids vif, comme avant.
--   consignes : consignes alimentaires libres (lues par les pros).
--   Les colonnes historiques (type_ration, marque, gamme, nb_repas,
--   ration_grammes, ration2_grammes, ration_kcal…) restent écrites pour les
--   écrans qui les lisent encore ; `notes` n'est plus touché.
--
-- marques_aliments
--   kcal_source        : 'fabricant' | 'composition' (estimation) | NULL
--   composition        : composition analytique saisie (% protéines, MG…)
--   tableau_croissance : [{age_mois, poids_adulte_kg, g_jour}] (chiot/chaton)
--   type_aliment       : + 'barf', 'menagere', 'autre' (chien / chat) et
--                        'foin', 'concentre', 'paturage', 'complement',
--                        'granules', 'legumes', 'graines' (autres espèces)
--                        (avant : croquettes / pâtée seulement)
--
-- Contrôles serveur (en plus de ceux de l'appli et du site) :
--   - densité énergétique > 0 et < 1000 kcal/100 g ;
--   - composition : chaque valeur 0–100, somme ≤ 100,5 % ;
--   - doublon d'aliment du catalogue (même marque + gamme + espèce + type) ;
--   - plan : 1 à 12 aliments, 1 à 6 repas, chaque repas ≥ 1 aliment,
--     grammes > 0 et ≤ 20 000.
-- Idempotent. Contraintes NOT VALID : les lignes existantes ne sont pas
-- revérifiées, seules les nouvelles écritures le sont.
--
-- ⚠️ À TESTER après exécution :
--   1. Enregistrer une alimentation mixte (appli et site) puis la relire.
--   2. Ajouter un aliment avec une densité de 0 → refusé.
--   3. Ajouter deux fois le même aliment → refusé (« existe déjà »).
-- ══════════════════════════════════════════════════════════════════════════

-- Colonnes de migration_alimentation_ration_stockee.sql (absentes du staging).
ALTER TABLE public.alimentations ADD COLUMN IF NOT EXISTS nb_repas INTEGER;
ALTER TABLE public.alimentations ADD COLUMN IF NOT EXISTS ration_grammes NUMERIC;
ALTER TABLE public.alimentations ADD COLUMN IF NOT EXISTS ration2_grammes NUMERIC;
ALTER TABLE public.alimentations ADD COLUMN IF NOT EXISTS ration_kcal NUMERIC;

ALTER TABLE public.alimentations ADD COLUMN IF NOT EXISTS plan JSONB;
ALTER TABLE public.alimentations ADD COLUMN IF NOT EXISTS consignes TEXT;

ALTER TABLE public.marques_aliments ADD COLUMN IF NOT EXISTS kcal_source TEXT;
ALTER TABLE public.marques_aliments ADD COLUMN IF NOT EXISTS composition JSONB;
ALTER TABLE public.marques_aliments ADD COLUMN IF NOT EXISTS tableau_croissance JSONB;

-- ── Contraintes simples ─────────────────────────────────────────────────
ALTER TABLE public.marques_aliments DROP CONSTRAINT IF EXISTS marques_aliments_densite_plausible;
ALTER TABLE public.marques_aliments ADD CONSTRAINT marques_aliments_densite_plausible
  CHECK (densite_kcal_100g IS NULL OR (densite_kcal_100g > 0 AND densite_kcal_100g < 1000)) NOT VALID;

ALTER TABLE public.marques_aliments DROP CONSTRAINT IF EXISTS marques_aliments_type_connu;
ALTER TABLE public.marques_aliments ADD CONSTRAINT marques_aliments_type_connu
  CHECK (type_aliment IS NULL OR type_aliment IN ('croquettes', 'pâtée', 'barf', 'menagere', 'autre',
    'foin', 'concentre', 'paturage', 'complement', 'granules', 'legumes', 'graines')) NOT VALID;

ALTER TABLE public.alimentations DROP CONSTRAINT IF EXISTS alimentations_rations_positives;
ALTER TABLE public.alimentations ADD CONSTRAINT alimentations_rations_positives
  CHECK ((ration_grammes IS NULL OR ration_grammes >= 0)
     AND (ration2_grammes IS NULL OR ration2_grammes >= 0)
     AND (ration_kcal IS NULL OR ration_kcal >= 0)
     AND (nb_repas IS NULL OR nb_repas BETWEEN 1 AND 6)) NOT VALID;

-- ── Catalogue : composition + doublons ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.pm_controler_marque_aliment()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  k TEXT;
  v NUMERIC;
  somme NUMERIC := 0;
BEGIN
  IF NEW.composition IS NOT NULL THEN
    IF jsonb_typeof(NEW.composition) <> 'object' THEN
      RAISE EXCEPTION 'Composition analytique invalide.' USING ERRCODE = '23514';
    END IF;
    FOR k IN SELECT jsonb_object_keys(NEW.composition) LOOP
      IF jsonb_typeof(NEW.composition -> k) <> 'number' THEN
        RAISE EXCEPTION 'Composition analytique : « % » n''est pas un nombre.', k USING ERRCODE = '23514';
      END IF;
      v := (NEW.composition ->> k)::numeric;
      IF v < 0 OR v > 100 THEN
        RAISE EXCEPTION 'Composition analytique : un pourcentage est compris entre 0 et 100.' USING ERRCODE = '23514';
      END IF;
      somme := somme + v;
    END LOOP;
    IF somme > 100.5 THEN
      RAISE EXCEPTION 'La somme des pourcentages dépasse 100 %%. Vérifiez les valeurs recopiées sur l''emballage.' USING ERRCODE = '23514';
    END IF;
  END IF;

  IF TG_OP = 'INSERT' AND EXISTS (
    SELECT 1 FROM public.marques_aliments m
    WHERE lower(btrim(m.marque)) = lower(btrim(NEW.marque))
      AND lower(btrim(m.gamme)) = lower(btrim(NEW.gamme))
      AND m.espece = NEW.espece
      AND coalesce(m.type_aliment, 'croquettes') = coalesce(NEW.type_aliment, 'croquettes')
  ) THEN
    RAISE EXCEPTION 'Cet aliment existe déjà dans le catalogue : sélectionnez-le dans la liste.' USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_controler_marque_aliment ON public.marques_aliments;
CREATE TRIGGER trg_controler_marque_aliment
  BEFORE INSERT OR UPDATE OF composition, marque, gamme ON public.marques_aliments
  FOR EACH ROW EXECUTE FUNCTION public.pm_controler_marque_aliment();

-- ── Plan par repas ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.pm_controler_plan_alimentation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  p JSONB := NEW.plan;
  nb_alim INT;
  r JSONB;
  it JSONB;
  a JSONB;
BEGIN
  IF p IS NULL THEN RETURN NEW; END IF;
  IF jsonb_typeof(p) <> 'object'
     OR jsonb_typeof(p -> 'aliments') IS DISTINCT FROM 'array'
     OR jsonb_typeof(p -> 'repas') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Plan d''alimentation invalide.' USING ERRCODE = '23514';
  END IF;
  nb_alim := jsonb_array_length(p -> 'aliments');
  IF nb_alim < 1 OR nb_alim > 12 THEN
    RAISE EXCEPTION 'Plan d''alimentation : de 1 à 12 aliments.' USING ERRCODE = '23514';
  END IF;
  IF jsonb_array_length(p -> 'repas') < 1 OR jsonb_array_length(p -> 'repas') > 6 THEN
    RAISE EXCEPTION 'Plan d''alimentation : de 1 à 6 repas par jour.' USING ERRCODE = '23514';
  END IF;
  FOR a IN SELECT * FROM jsonb_array_elements(p -> 'aliments') LOOP
    IF coalesce(btrim(a ->> 'marque'), '') = '' THEN
      RAISE EXCEPTION 'Plan d''alimentation : aliment sans marque.' USING ERRCODE = '23514';
    END IF;
    IF a ? 'kcal' AND jsonb_typeof(a -> 'kcal') <> 'null' THEN
      IF jsonb_typeof(a -> 'kcal') <> 'number' OR (a ->> 'kcal')::numeric <= 0 OR (a ->> 'kcal')::numeric >= 1000 THEN
        RAISE EXCEPTION 'Plan d''alimentation : valeur énergétique invalide.' USING ERRCODE = '23514';
      END IF;
    END IF;
  END LOOP;
  FOR r IN SELECT * FROM jsonb_array_elements(p -> 'repas') LOOP
    IF jsonb_typeof(r -> 'items') IS DISTINCT FROM 'array' OR jsonb_array_length(r -> 'items') = 0 THEN
      RAISE EXCEPTION 'Plan d''alimentation : chaque repas contient au moins un aliment.' USING ERRCODE = '23514';
    END IF;
    FOR it IN SELECT * FROM jsonb_array_elements(r -> 'items') LOOP
      IF jsonb_typeof(it -> 'a') IS DISTINCT FROM 'number'
         OR (it ->> 'a')::numeric < 0 OR (it ->> 'a')::numeric >= nb_alim THEN
        RAISE EXCEPTION 'Plan d''alimentation : aliment de repas inconnu.' USING ERRCODE = '23514';
      END IF;
      IF it ? 'g' AND jsonb_typeof(it -> 'g') <> 'null' THEN
        IF jsonb_typeof(it -> 'g') <> 'number' OR (it ->> 'g')::numeric <= 0 OR (it ->> 'g')::numeric > 20000 THEN
          RAISE EXCEPTION 'Plan d''alimentation : quantité invalide (en grammes, supérieure à 0).' USING ERRCODE = '23514';
        END IF;
      END IF;
    END LOOP;
  END LOOP;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_controler_plan_alimentation ON public.alimentations;
CREATE TRIGGER trg_controler_plan_alimentation
  BEFORE INSERT OR UPDATE OF plan ON public.alimentations
  FOR EACH ROW EXECUTE FUNCTION public.pm_controler_plan_alimentation();

NOTIFY pgrst, 'reload schema';

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK
-- ══════════════════════════════════════════════════════════════════════════
-- DROP TRIGGER IF EXISTS trg_controler_plan_alimentation ON public.alimentations;
-- DROP TRIGGER IF EXISTS trg_controler_marque_aliment ON public.marques_aliments;
-- DROP FUNCTION IF EXISTS public.pm_controler_plan_alimentation();
-- DROP FUNCTION IF EXISTS public.pm_controler_marque_aliment();
-- ALTER TABLE public.marques_aliments DROP CONSTRAINT IF EXISTS marques_aliments_densite_plausible;
-- ALTER TABLE public.marques_aliments DROP CONSTRAINT IF EXISTS marques_aliments_type_connu;
-- ALTER TABLE public.alimentations DROP CONSTRAINT IF EXISTS alimentations_rations_positives;
-- (colonnes conservées : sans effet si inutilisées)
