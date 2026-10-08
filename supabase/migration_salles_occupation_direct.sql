-- ════════════════════════════════════════════════════════════════════════
-- Clinique vétérinaire — salles en direct.
-- (Après migration_clinique_salle_praticien.sql.)
--
-- Décisions (08/10/2026) :
--   • Le lieu d'un RDV se choisit à la validation / à la modification :
--     « À domicile » ou une salle — refusé si la salle choisie est occupée.
--   • Occupation ponctuelle d'une salle (radio pendant une consultation,
--     opération programmée…) : occupations_salle, contrôlée en base comme
--     les RDV (pas de double réservation).
--   • « Libérer la salle » : rdv.salle_liberee_at / occupations_salle.
--     liberee_at — la salle redevient libre tout de suite.
--   • Tous les praticiens de la clinique voient l'état des salles ; mises à
--     jour en temps réel (publication supabase_realtime).
--   • Salle par défaut : celle affectée au praticien sur son créneau
--     (creneaux_pro.salle_id) — y compris quand le praticien change (« peu
--     importe » attribué, modification) ; sinon une salle libre du bon type.
--
-- Multi-profil : scopé au profil clinique.
-- Idempotent. Staging d'abord.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS salle_liberee_at timestamptz;

CREATE TABLE IF NOT EXISTS public.occupations_salle (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clinique_profile_id  uuid NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  salle_id             uuid NOT NULL REFERENCES salles_clinique(id) ON DELETE CASCADE,
  debut                timestamptz NOT NULL,
  fin                  timestamptz NOT NULL,
  motif                text,
  rdv_id               uuid REFERENCES rdv(id) ON DELETE SET NULL,
  -- Praticien occupé (NULL = titulaire de la clinique).
  praticien_profile_id uuid REFERENCES user_profiles(id) ON DELETE SET NULL,
  cree_par_uid         text,
  liberee_at           timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT occupations_salle_fin_apres_debut CHECK (fin > debut)
);
CREATE INDEX IF NOT EXISTS idx_occupations_salle_clinique ON public.occupations_salle (clinique_profile_id, debut);
CREATE INDEX IF NOT EXISTS idx_occupations_salle_salle ON public.occupations_salle (salle_id, debut);
ALTER TABLE public.occupations_salle ENABLE ROW LEVEL SECURITY;

-- Équipe de la clinique : titulaire / cogérant / équipe agenda, et tout
-- employé praticien ou ASV de CE profil.
DROP POLICY IF EXISTS occupations_salle_equipe ON public.occupations_salle;
CREATE POLICY occupations_salle_equipe ON public.occupations_salle
  FOR ALL TO anon, authenticated
  USING (public.pm_gere_clinique(clinique_profile_id)
    OR public.pm_employe_profil(clinique_profile_id, ARRAY['vet_agenda', 'vet_patients', 'vet_cr_rediger', 'vet_cr_valider']))
  WITH CHECK (public.pm_gere_clinique(clinique_profile_id)
    OR public.pm_employe_profil(clinique_profile_id, ARRAY['vet_agenda', 'vet_patients', 'vet_cr_rediger', 'vet_cr_valider']));

-- ── Salle occupée sur [p_debut, p_fin[ ? (fin effective = libération) ──────
CREATE OR REPLACE FUNCTION public.pm_salle_occupee(
  p_salle uuid, p_debut timestamptz, p_fin timestamptz,
  p_exclure_rdv uuid DEFAULT NULL, p_exclure_occ uuid DEFAULT NULL)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM rdv r
     WHERE r.salle_id = p_salle
       AND r.statut IN ('confirme', 'demande')
       AND r.id IS DISTINCT FROM p_exclure_rdv
       AND r.date_heure < p_fin
       AND least(r.date_heure + make_interval(mins => coalesce(r.duree_minutes, 30)),
                 coalesce(r.salle_liberee_at, 'infinity'::timestamptz)) > p_debut
  ) OR EXISTS (
    SELECT 1 FROM occupations_salle o
     WHERE o.salle_id = p_salle
       AND o.id IS DISTINCT FROM p_exclure_occ
       AND o.debut < p_fin
       AND least(o.fin, coalesce(o.liberee_at, 'infinity'::timestamptz)) > p_debut
  );
$$;
GRANT EXECUTE ON FUNCTION public.pm_salle_occupee(uuid, timestamptz, timestamptz, uuid, uuid) TO anon, authenticated;

-- ── Salles d'une clinique et leur disponibilité sur un créneau ───────────
CREATE OR REPLACE FUNCTION public.pm_salles_dispo(
  p_pro_profile_id uuid, p_debut timestamptz, p_fin timestamptz, p_exclure_rdv uuid DEFAULT NULL)
RETURNS TABLE (id uuid, nom text, type_salle text, libre boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT s.id, s.nom, s.type_salle,
         NOT public.pm_salle_occupee(s.id, p_debut, p_fin, p_exclure_rdv, NULL)
    FROM salles_clinique s
   WHERE s.clinique_profile_id = p_pro_profile_id AND s.actif
     AND (public.pm_gere_clinique(p_pro_profile_id)
          OR public.pm_employe_profil(p_pro_profile_id, ARRAY['vet_agenda', 'vet_patients', 'vet_cr_rediger', 'vet_cr_valider']))
   ORDER BY s.ordre, s.created_at;
$$;
GRANT EXECUTE ON FUNCTION public.pm_salles_dispo(uuid, timestamptz, timestamptz, uuid) TO anon, authenticated;

-- ── Contrôle d'une occupation ponctuelle ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.pm_occupation_salle_controle()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Libération (ou simple mise à jour sans changement d'horaire / de salle).
  IF TG_OP = 'UPDATE'
     AND NEW.salle_id = OLD.salle_id AND NEW.debut = OLD.debut AND NEW.fin = OLD.fin THEN
    RETURN NEW;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('rdv_clinique_' || NEW.clinique_profile_id::text));
  IF NOT EXISTS (SELECT 1 FROM salles_clinique s
                  WHERE s.id = NEW.salle_id AND s.clinique_profile_id = NEW.clinique_profile_id) THEN
    RAISE EXCEPTION 'Salle inconnue pour cette clinique.' USING ERRCODE = 'P0001';
  END IF;
  IF public.pm_salle_occupee(NEW.salle_id, NEW.debut, NEW.fin, NULL, NEW.id) THEN
    RAISE EXCEPTION 'Cette salle est déjà occupée sur ce créneau.' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_occupation_salle_controle ON public.occupations_salle;
CREATE TRIGGER trg_occupation_salle_controle
  BEFORE INSERT OR UPDATE ON public.occupations_salle
  FOR EACH ROW EXECUTE FUNCTION public.pm_occupation_salle_controle();

-- ── Contrôle d'un RDV de clinique (remplace la version de
--    migration_clinique_salle_praticien.sql) : occupations ponctuelles et
--    libérations prises en compte ; salle choisie explicitement mais occupée
--    → refus, y compris pour le pro.
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

-- ── Plages occupées (réservation en ligne) : + occupations ponctuelles ───
-- Même signature que migration_clinique_rdv.sql ; les occupations bloquent
-- leur salle et leur praticien. Fin effective = libération éventuelle.
CREATE OR REPLACE FUNCTION public.pm_plages_occupees(p_pro_profile_id text, p_debut timestamptz, p_fin timestamptz)
RETURNS TABLE (
  date_heure timestamptz, duree_minutes integer, statut text, motif text,
  praticien_profile_id uuid, salle_id uuid, employe_id bigint,
  lieu_lat numeric, lieu_lng numeric, indisponible boolean
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT r.date_heure, coalesce(r.duree_minutes, 30), r.statut, r.motif,
         r.instructeur_profile_id, r.salle_id, r.employe_id,
         round(r.lieu_lat, 2), round(r.lieu_lng, 2), false
    FROM rdv r
   WHERE r.pro_profile_id = p_pro_profile_id
     AND r.statut IN ('confirme', 'demande')
     AND r.date_heure < p_fin
     AND r.date_heure + make_interval(mins => coalesce(r.duree_minutes, 30)) > p_debut
  UNION ALL
  SELECT e.date_debut,
         greatest(1, coalesce(e.duree_minutes,
           (extract(epoch FROM (coalesce(e.date_fin, e.date_debut + interval '1 hour') - e.date_debut)) / 60)::int)),
         'indisponible', NULL, e.praticien_profile_id, NULL, NULL, NULL, NULL, true
    FROM agenda_events e
   WHERE e.type = 'indisponible'
     AND coalesce(nullif(e.pro_profile_id, ''), e.profile_id::text) = p_pro_profile_id
     AND e.date_debut < p_fin
     AND coalesce(e.date_fin, e.date_debut + interval '1 hour') > p_debut
  UNION ALL
  SELECT o.debut,
         greatest(1, (extract(epoch FROM (least(o.fin, coalesce(o.liberee_at, o.fin)) - o.debut)) / 60)::int),
         'occupation', o.motif, o.praticien_profile_id, o.salle_id, NULL, NULL, NULL, false
    FROM occupations_salle o
   WHERE o.clinique_profile_id::text = p_pro_profile_id
     AND o.debut < p_fin
     AND least(o.fin, coalesce(o.liberee_at, o.fin)) > p_debut
     AND least(o.fin, coalesce(o.liberee_at, o.fin)) > o.debut;
$$;
GRANT EXECUTE ON FUNCTION public.pm_plages_occupees(text, timestamptz, timestamptz) TO anon, authenticated;

COMMIT;

-- ── Temps réel : état des salles mis à jour chez tous les praticiens ─────
DO $$
BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.occupations_salle; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.rdv;               EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;
