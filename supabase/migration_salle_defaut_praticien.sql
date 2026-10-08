-- ════════════════════════════════════════════════════════════════════════
-- Clinique vétérinaire — salle par défaut de chaque praticien.
-- (Après migration_salles_occupation_direct.sql.)
--
-- Décisions (08/10/2026) : chaque praticien a une salle par défaut, réglée
-- une fois dans « Salles & motifs » — plus besoin de reprendre ses créneaux.
-- Ordre de choix de la salle d'un RDV :
--   1. salle choisie explicitement (validation / modification) ;
--   2. salle du créneau du praticien (creneaux_pro.salle_id — ponctuel) ;
--   3. salle par défaut du praticien (titulaire : user_profiles.salle_defaut_id
--      du profil clinique ; vétérinaire employé : employes.salle_defaut_id) ;
--   4. une salle libre du type du motif.
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS salle_defaut_id uuid REFERENCES salles_clinique(id) ON DELETE SET NULL;
ALTER TABLE public.employes      ADD COLUMN IF NOT EXISTS salle_defaut_id uuid REFERENCES salles_clinique(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.pm_rdv_controle_clinique()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type_profil text;
  v_debut timestamptz := NEW.date_heure;
  v_fin   timestamptz := NEW.date_heure + make_interval(mins => coalesce(NEW.duree_minutes, 30));
  v_client boolean := coalesce(NEW.cree_par_pro, false) = false;
  v_cle   text := public.pm_cle_motif(NEW.motif);
  v_type_salle text;
  v_a_salles boolean;
  v_salle uuid;
  v_pref  uuid;
  v_local timestamp := NEW.date_heure AT TIME ZONE 'Europe/Paris';
  v_salle_choisie boolean;
BEGIN
  IF NEW.statut NOT IN ('confirme', 'demande') OR NEW.pro_profile_id IS NULL OR NEW.date_heure IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT up.profile_type INTO v_type_profil FROM user_profiles up WHERE up.id::text = NEW.pro_profile_id;
  IF v_type_profil IS DISTINCT FROM 'veterinaire' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE'
     AND NEW.date_heure IS NOT DISTINCT FROM OLD.date_heure
     AND NEW.duree_minutes IS NOT DISTINCT FROM OLD.duree_minutes
     AND NEW.instructeur_profile_id IS NOT DISTINCT FROM OLD.instructeur_profile_id
     AND NEW.salle_id IS NOT DISTINCT FROM OLD.salle_id
     AND NEW.lieu_lat IS NOT DISTINCT FROM OLD.lieu_lat
     AND NEW.lieu IS NOT DISTINCT FROM OLD.lieu
     AND OLD.statut IN ('confirme', 'demande') THEN
    RETURN NEW;  -- ex. libération de la salle, notes, statut
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('rdv_clinique_' || NEW.pro_profile_id));

  IF v_client AND EXISTS (
    SELECT 1 FROM public.pm_plages_occupees(NEW.pro_profile_id, v_debut, v_fin) p
     WHERE p.praticien_profile_id IS NOT DISTINCT FROM NEW.instructeur_profile_id
       AND p.date_heure < v_fin
       AND p.date_heure + make_interval(mins => p.duree_minutes) > v_debut
       AND NOT (TG_OP = 'UPDATE' AND p.date_heure = OLD.date_heure AND NOT p.indisponible
                AND p.praticien_profile_id IS NOT DISTINCT FROM OLD.instructeur_profile_id)
  ) THEN
    RAISE EXCEPTION 'Ce créneau vient d''être pris. Choisissez-en un autre.' USING ERRCODE = 'P0001';
  END IF;

  -- À domicile (motif, adresse géolocalisée ou lieu « À domicile ») : aucune salle.
  IF v_cle = 'visite_domicile' OR NEW.lieu_lat IS NOT NULL OR NEW.lieu ILIKE '%domicile%' THEN
    NEW.salle_id := NULL;
    RETURN NEW;
  END IF;

  -- Changement de praticien sans choix de salle (« peu importe » attribué,
  -- modification) : la salle suit le praticien — celle affectée à son
  -- créneau en priorité (v_pref), sinon une salle libre du bon type.
  IF TG_OP = 'UPDATE'
     AND NEW.instructeur_profile_id IS DISTINCT FROM OLD.instructeur_profile_id
     AND NEW.salle_id IS NOT DISTINCT FROM OLD.salle_id THEN
    NEW.salle_id := NULL;
  END IF;

  -- Salle choisie explicitement (validation / modification par le pro).
  v_salle_choisie := NEW.salle_id IS NOT NULL
    AND (TG_OP = 'INSERT' OR NEW.salle_id IS DISTINCT FROM OLD.salle_id);
  IF v_salle_choisie AND NOT v_client THEN
    IF NOT EXISTS (SELECT 1 FROM salles_clinique s
                    WHERE s.id = NEW.salle_id AND s.clinique_profile_id::text = NEW.pro_profile_id) THEN
      NEW.salle_id := NULL;
      RETURN NEW;
    END IF;
    IF public.pm_salle_occupee(NEW.salle_id, v_debut, v_fin, NEW.id, NULL) THEN
      RAISE EXCEPTION 'Cette salle est déjà occupée sur ce créneau.' USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
  END IF;

  SELECT EXISTS (SELECT 1 FROM salles_clinique s WHERE s.clinique_profile_id::text = NEW.pro_profile_id AND s.actif)
    INTO v_a_salles;
  IF NOT v_a_salles THEN RETURN NEW; END IF;

  SELECT coalesce(up.salles_par_motif ->> v_cle, 'consultation') INTO v_type_salle
    FROM user_profiles up WHERE up.id::text = NEW.pro_profile_id;

  -- Salle attribuée au praticien sur son créneau à cette heure (choix
  -- ponctuel, prioritaire).
  SELECT c.salle_id INTO v_pref
    FROM creneaux_pro c
   WHERE c.pro_profile_id = NEW.pro_profile_id
     AND c.praticien_profile_id IS NOT DISTINCT FROM NEW.instructeur_profile_id
     AND c.salle_id IS NOT NULL
     AND c.date = v_local::date
     AND c.heure_debut <= v_local::time AND c.heure_fin > v_local::time
   LIMIT 1;

  -- Sinon : salle par défaut du praticien (titulaire : profil clinique ;
  -- vétérinaire employé : sa fiche employé).
  IF v_pref IS NULL THEN
    IF NEW.instructeur_profile_id IS NULL THEN
      SELECT up.salle_defaut_id INTO v_pref FROM user_profiles up WHERE up.id::text = NEW.pro_profile_id;
    ELSE
      SELECT e.salle_defaut_id INTO v_pref FROM employes e
       WHERE e.eleveur_profile_id::text = NEW.pro_profile_id
         AND e.employe_profile_id = NEW.instructeur_profile_id AND e.actif = true
       LIMIT 1;
    END IF;
  END IF;

  SELECT s.id INTO v_salle
    FROM salles_clinique s
   WHERE s.clinique_profile_id::text = NEW.pro_profile_id AND s.actif
     AND s.type_salle = v_type_salle
     AND (NEW.salle_id IS NULL OR s.id = NEW.salle_id)
     AND NOT public.pm_salle_occupee(s.id, v_debut, v_fin, NEW.id, NULL)
   ORDER BY (s.id = v_pref) DESC NULLS LAST, s.ordre, s.created_at
   LIMIT 1;

  IF v_salle IS NULL THEN
    IF v_client THEN
      RAISE EXCEPTION 'Plus de salle disponible sur ce créneau. Choisissez-en un autre.' USING ERRCODE = 'P0001';
    END IF;
    IF NEW.salle_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM salles_clinique WHERE id = NEW.salle_id) THEN
      NEW.salle_id := NULL;
    END IF;
    RETURN NEW;
  END IF;
  NEW.salle_id := v_salle;
  RETURN NEW;
END;
$$;

COMMIT;

-- Nouvelle colonne publique de user_profiles : vue masquée + droits.
SELECT public.pm_recreer_vues_perso();
SELECT public.pm_appliquer_droits_perso();
