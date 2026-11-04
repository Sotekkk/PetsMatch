-- Planning du vétérinaire : plus de doublon avec le RDV d'intervention (04/11/2026).
-- « Chirurgie — Détartrage (Luna) » à 8 h fixes s'ajoutait au RDV, alors que le RDV
-- et le temps de bloc sont déjà dans l'agenda (dépôt de Luna à 10 h 15).
--   • Chirurgie rattachée à un RDV (rdv.chirurgie_id) : pas d'événement.
--   • Chirurgie saisie depuis la fiche, sans RDV : événement inchangé.
--   • RDV rattaché à une autre chirurgie : l'ancienne, si elle reste prévue et sans
--     RDV, retrouve son événement. RDV annulé : pas d'événement (il ne reviendrait
--     à 8 h que pour une intervention annulée).
-- Événements retirés gardés dans sauv_rappels_sante_20261104.
-- Reprend la fonction de migration_chirurgie_planning_profil.sql. Idempotent.

BEGIN;

CREATE OR REPLACE FUNCTION public.pm_chirurgie_planning_veto()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c record;
  v_profil uuid;
  v_nom text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM agenda_events WHERE chirurgie_id = OLD.id::text;
    RETURN OLD;
  END IF;
  c := NEW;
  DELETE FROM agenda_events WHERE chirurgie_id = c.id::text;
  IF c.vet_id IS NULL OR c.statut IS DISTINCT FROM 'prevu' OR c.date IS NULL THEN
    RETURN NEW;
  END IF;
  -- Rattachée à un RDV : déjà dans l'agenda.
  IF EXISTS (SELECT 1 FROM rdv r WHERE r.chirurgie_id = c.id::text) THEN
    RETURN NEW;
  END IF;

  v_profil := pm_profil_chirurgie(c.id::text, c.pro_profile_id, c.vet_id);
  SELECT nom INTO v_nom FROM animaux WHERE id::text = c.animal_id::text;

  INSERT INTO agenda_events (uid, titre, type, date_debut, animal_id, notes, chirurgie_id, pro_profile_id, profile_id)
  VALUES (
    c.vet_id,
    initcap(coalesce(c.type, 'chirurgie')) || ' — ' || coalesce(nullif(trim(c.intitule), ''), 'intervention')
      || coalesce(' (' || v_nom || ')', ''),
    'autre',
    (left(c.date::text, 10)::date + time '08:00') AT TIME ZONE 'Europe/Paris',
    c.animal_id::text,
    nullif(concat_ws(E'\n', 'Pré-op : ' || nullif(trim(c.protocole_preop), ''), 'Post-op : ' || nullif(trim(c.protocole_postop), '')), ''),
    c.id::text,
    v_profil,
    v_profil);
  RETURN NEW;
EXCEPTION WHEN others THEN
  RETURN NEW; -- le planning ne doit jamais bloquer l'enregistrement de la fiche
END;
$$;

-- La chirurgie est créée avant d'être rattachée au RDV : l'événement est retiré au rattachement.
CREATE OR REPLACE FUNCTION public.pm_rdv_chirurgie_planning()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.chirurgie_id IS NOT NULL THEN
    DELETE FROM agenda_events WHERE chirurgie_id = NEW.chirurgie_id;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.chirurgie_id IS NOT NULL AND OLD.chirurgie_id IS DISTINCT FROM NEW.chirurgie_id THEN
    -- Relance pm_chirurgie_planning_veto : événement rendu si elle reste prévue et sans RDV.
    UPDATE chirurgies SET statut = statut WHERE id::text = OLD.chirurgie_id;
  END IF;
  RETURN NEW;
EXCEPTION WHEN others THEN
  RETURN NEW; -- le planning ne doit jamais bloquer le RDV
END;
$$;

DROP TRIGGER IF EXISTS trg_rdv_chirurgie_planning ON public.rdv;
CREATE TRIGGER trg_rdv_chirurgie_planning
  AFTER INSERT OR UPDATE OF chirurgie_id ON public.rdv
  FOR EACH ROW EXECUTE FUNCTION public.pm_rdv_chirurgie_planning();

-- Événements existants des chirurgies rattachées à un RDV.
WITH suppr AS (
  DELETE FROM agenda_events e USING rdv r
   WHERE e.chirurgie_id IS NOT NULL AND r.chirurgie_id = e.chirurgie_id
  RETURNING e.*
)
INSERT INTO public.sauv_rappels_sante_20261104 (source, ligne)
SELECT 'agenda_events_chirurgie', to_jsonb(s) FROM (SELECT DISTINCT ON (id) * FROM suppr) s;

COMMIT;
