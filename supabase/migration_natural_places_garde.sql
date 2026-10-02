-- ════════════════════════════════════════════════════════════════════════
-- natural_places : la policy natural_places_update laisse tout compte
-- connecté modifier un lieu VALIDÉ (nécessaire : alerte cyanobactéries,
-- difficulté communautaire, note / nb d'avis recalculés après un avis) —
-- mais elle autorisait aussi à renommer, déplacer, vider la description,
-- retirer les photos ou dépublier n'importe quel lieu.
-- Garde-fou : hors auteur du lieu et admin, seules ces colonnes peuvent
-- changer. (Appels service / sans jeton : non concernés.)
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

CREATE OR REPLACE FUNCTION public.pm_natural_places_garde()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_sub text := auth.jwt() ->> 'sub';
  v_libres text[] := ARRAY['alerte_cyano', 'alerte_cyano_date', 'alerte_cyano_profile_id',
                           'alerte_cyano_lat', 'alerte_cyano_lng', 'alerte_cyano_statut',
                           'alerte_cyano_photo_url', 'niveau_difficulte', 'nb_avis',
                           'note_moyenne', 'updated_at'];
BEGIN
  IF v_sub IS NULL OR v_sub = OLD.submitted_by_uid OR is_admin_uid(v_sub) THEN
    RETURN NEW;
  END IF;
  IF (to_jsonb(NEW) - v_libres) IS DISTINCT FROM (to_jsonb(OLD) - v_libres) THEN
    RAISE EXCEPTION 'Modification réservée à l''auteur du lieu ou à un administrateur'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_natural_places_garde ON public.natural_places;
CREATE TRIGGER trg_natural_places_garde
  BEFORE UPDATE ON public.natural_places
  FOR EACH ROW EXECUTE FUNCTION public.pm_natural_places_garde();

COMMIT;
