-- ════════════════════════════════════════════════════════════════════════
-- Clinique : salle attribuée à un praticien sur ses créneaux.
-- (Après migration_clinique_rdv.sql.)
-- Le gérant (ou l'équipe « agenda ») indique la salle de consultation
-- qu'occupe un vétérinaire sur ses disponibilités. À la réservation, ses RDV
-- vont dans cette salle en priorité (si elle est du type demandé par le motif
-- et libre), sinon dans une autre salle libre du même type.
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════

ALTER TABLE creneaux_pro ADD COLUMN IF NOT EXISTS salle_id uuid REFERENCES salles_clinique(id) ON DELETE SET NULL;

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
     AND OLD.statut IN ('confirme', 'demande') THEN
    RETURN NEW;
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

  IF v_cle = 'visite_domicile' OR NEW.lieu_lat IS NOT NULL THEN
    NEW.salle_id := NULL;
    RETURN NEW;
  END IF;
  SELECT EXISTS (SELECT 1 FROM salles_clinique s WHERE s.clinique_profile_id::text = NEW.pro_profile_id AND s.actif)
    INTO v_a_salles;
  IF NOT v_a_salles THEN RETURN NEW; END IF;

  SELECT coalesce(up.salles_par_motif ->> v_cle, 'consultation') INTO v_type_salle
    FROM user_profiles up WHERE up.id::text = NEW.pro_profile_id;

  -- Salle attribuée au praticien sur son créneau à cette heure.
  SELECT c.salle_id INTO v_pref
    FROM creneaux_pro c
   WHERE c.pro_profile_id = NEW.pro_profile_id
     AND c.praticien_profile_id IS NOT DISTINCT FROM NEW.instructeur_profile_id
     AND c.salle_id IS NOT NULL
     AND c.date = v_local::date
     AND c.heure_debut <= v_local::time AND c.heure_fin > v_local::time
   LIMIT 1;

  SELECT s.id INTO v_salle
    FROM salles_clinique s
   WHERE s.clinique_profile_id::text = NEW.pro_profile_id AND s.actif
     AND s.type_salle = v_type_salle
     AND (NEW.salle_id IS NULL OR s.id = NEW.salle_id)
     AND NOT EXISTS (
       SELECT 1 FROM rdv r
        WHERE r.salle_id = s.id AND r.statut IN ('confirme', 'demande')
          AND r.id IS DISTINCT FROM NEW.id
          AND r.date_heure < v_fin
          AND r.date_heure + make_interval(mins => coalesce(r.duree_minutes, 30)) > v_debut)
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

-- ── Choix du vétérinaire par le client (réglage de la clinique) ─────────
-- true (défaut) : à la réservation, le client choisit « peu importe » ou un
-- vétérinaire ; false : premier vétérinaire libre, sans choix proposé.
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS rdv_choix_praticien boolean NOT NULL DEFAULT true;
SELECT public.pm_recreer_vues_perso();
SELECT public.pm_appliquer_droits_perso();
