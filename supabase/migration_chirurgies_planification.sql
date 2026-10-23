-- ════════════════════════════════════════════════════════════════════════
-- Chirurgie / hospitalisation prévue : rappels et planning du vétérinaire.
--
--   • rappel_j7_envoye / rappel_j1_envoye / rappel_j0_envoye : notifications
--     J-7, la veille et le jour même (Cloud Function sendChirurgieReminders,
--     8 h) au(x) propriétaire(s) et au vétérinaire qui a saisi l'intervention.
--     Remis à zéro si la date ou le statut change (nouveaux rappels).
--   • Saisie par un vétérinaire (vet_id) et « prévue » : l'intervention entre
--     dans SON planning (agenda_events, profil vétérinaire, chirurgie_id) ;
--     l'événement suit la fiche : date modifiée → déplacé, réalisée / annulée
--     / supprimée → retiré.
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE public.chirurgies ADD COLUMN IF NOT EXISTS rappel_j7_envoye boolean NOT NULL DEFAULT false;
ALTER TABLE public.chirurgies ADD COLUMN IF NOT EXISTS rappel_j1_envoye boolean NOT NULL DEFAULT false;
ALTER TABLE public.chirurgies ADD COLUMN IF NOT EXISTS rappel_j0_envoye boolean NOT NULL DEFAULT false;
ALTER TABLE public.agenda_events ADD COLUMN IF NOT EXISTS chirurgie_id text;
CREATE INDEX IF NOT EXISTS idx_agenda_events_chirurgie ON public.agenda_events (chirurgie_id) WHERE chirurgie_id IS NOT NULL;

-- Date ou statut changé : les rappels repartent de zéro.
CREATE OR REPLACE FUNCTION public.pm_chirurgie_rappels_reset()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.date IS DISTINCT FROM OLD.date OR NEW.statut IS DISTINCT FROM OLD.statut THEN
    NEW.rappel_j7_envoye := false;
    NEW.rappel_j1_envoye := false;
    NEW.rappel_j0_envoye := false;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_chirurgie_rappels_reset ON public.chirurgies;
CREATE TRIGGER trg_chirurgie_rappels_reset
  BEFORE UPDATE ON public.chirurgies
  FOR EACH ROW EXECUTE FUNCTION public.pm_chirurgie_rappels_reset();

-- Planning du vétérinaire qui a saisi l'intervention.
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

  -- Profil vétérinaire (ou santé) de ce compte, le principal d'abord.
  SELECT id INTO v_profil FROM user_profiles
   WHERE uid = c.vet_id AND (cat_pro IN ('veterinaire', 'sante') OR profile_type IN ('veterinaire', 'sante'))
   ORDER BY is_main DESC NULLS LAST LIMIT 1;
  IF v_profil IS NULL THEN
    SELECT id INTO v_profil FROM user_profiles WHERE uid = c.vet_id AND is_main LIMIT 1;
  END IF;
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

DROP TRIGGER IF EXISTS trg_chirurgie_planning_veto ON public.chirurgies;
CREATE TRIGGER trg_chirurgie_planning_veto
  AFTER INSERT OR UPDATE OF date, statut, intitule, type, vet_id OR DELETE ON public.chirurgies
  FOR EACH ROW EXECUTE FUNCTION public.pm_chirurgie_planning_veto();

-- Interventions déjà prévues par un vétérinaire : entrées dans son planning.
UPDATE public.chirurgies SET statut = statut
 WHERE vet_id IS NOT NULL AND statut = 'prevu' AND left(date::text, 10)::date >= current_date;

COMMIT;
