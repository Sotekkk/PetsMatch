-- Planning du vétérinaire : intervention dans le BON profil (04/11/2026).
-- pm_chirurgie_planning_veto prenait « le profil vétérinaire ou santé du compte,
-- le principal d'abord » : sur un compte avec un profil ostéo et un profil
-- vétérinaire, « Chirurgie — Détartrage (Luna) » tombait dans l'agenda de l'ostéo.
-- Profil retenu : celui de la chirurgie, sinon celui du RDV qui y est rattaché,
-- sinon le profil vétérinaire du compte, puis santé. Événements existants corrigés.
-- Reprend la fonction de migration_chirurgies_planification.sql. Idempotent.

BEGIN;

-- Absente du staging, déjà là en prod (migration_chirurgies_planification.sql).
ALTER TABLE public.agenda_events ADD COLUMN IF NOT EXISTS chirurgie_id text;
CREATE INDEX IF NOT EXISTS idx_agenda_events_chirurgie ON public.agenda_events (chirurgie_id) WHERE chirurgie_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.pm_profil_chirurgie(p_chirurgie_id text, p_pro_profile_id uuid, p_vet_id text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    p_pro_profile_id,
    (SELECT NULLIF(r.pro_profile_id, '')::uuid FROM rdv r
      WHERE r.chirurgie_id = p_chirurgie_id AND NULLIF(r.pro_profile_id, '') IS NOT NULL LIMIT 1),
    (SELECT u.id FROM user_profiles u
      WHERE u.uid = p_vet_id AND (u.cat_pro IN ('veterinaire', 'sante') OR u.profile_type IN ('veterinaire', 'sante'))
      ORDER BY (u.cat_pro = 'veterinaire' OR u.profile_type = 'veterinaire') DESC NULLS LAST, u.is_main DESC NULLS LAST LIMIT 1),
    (SELECT u.id FROM user_profiles u WHERE u.uid = p_vet_id AND u.is_main LIMIT 1));
$function$;

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

DROP TRIGGER IF EXISTS trg_chirurgie_planning_veto ON public.chirurgies;
CREATE TRIGGER trg_chirurgie_planning_veto
  AFTER INSERT OR UPDATE OF date, statut, intitule, type, vet_id, pro_profile_id OR DELETE ON public.chirurgies
  FOR EACH ROW EXECUTE FUNCTION public.pm_chirurgie_planning_veto();

-- Événements existants : replacés dans le bon profil.
UPDATE agenda_events e
   SET pro_profile_id = p.id::text, profile_id = p.id
  FROM chirurgies c
  CROSS JOIN LATERAL (SELECT pm_profil_chirurgie(c.id::text, c.pro_profile_id, c.vet_id) AS id) p
 WHERE e.chirurgie_id = c.id::text AND p.id IS NOT NULL
   AND (e.pro_profile_id IS DISTINCT FROM p.id::text OR e.profile_id IS DISTINCT FROM p.id);

COMMIT;
