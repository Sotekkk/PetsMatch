-- ════════════════════════════════════════════════════════════════════════
-- Prise de RDV en clinique : praticiens, salles typées, plages occupées.
-- (Suite de migration_clinique_equipe.sql — à lancer après.)
--
-- Décisions (07/10/2026) :
--   • le client choisit « peu importe » ou un vétérinaire précis ;
--   • disponibilités PAR praticien (creneaux_pro.praticien_profile_id,
--     null = titulaire) — gérées par le gérant / l'équipe avec vet_agenda,
--     et par chaque praticien pour les siennes ;
--   • salles typées (consultation, chirurgie, imagerie…) ; chaque motif
--     occupe un type de salle (user_profiles.salles_par_motif) ;
--   • bloquent un créneau : RDV clients, RDV saisis par le pro,
--     indisponibilités (agenda_events type 'indisponible'), salle pleine ;
--   • anti double-réservation : vérifié en base à l'insertion (verrou par
--     profil), le pro peut toujours forcer (cree_par_pro).
--
-- CORRECTIF (tous métiers) : depuis la RLS, un client ne lit que SES RDV —
-- la réservation ne voyait plus les créneaux pris par les autres clients.
-- pm_plages_occupees() expose les plages occupées SANS donnée personnelle
-- (lieu arrondi ~1 km, utile au calcul de trajet).
--
-- Multi-profil : tout est scopé au PROFIL pro (pro_profile_id).
-- Idempotent. Staging d'abord (scripts/staging/test_clinique_rdv.sql).
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── Salles ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.salles_clinique (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clinique_profile_id uuid NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  nom                 text NOT NULL,
  type_salle          text NOT NULL DEFAULT 'consultation',
  actif               boolean NOT NULL DEFAULT true,
  ordre               integer NOT NULL DEFAULT 0,
  created_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_salles_clinique_profil ON public.salles_clinique (clinique_profile_id);
ALTER TABLE public.salles_clinique ENABLE ROW LEVEL SECURITY;

-- Le titulaire (ou cogérant / équipe « agenda ») gère ses salles.
CREATE OR REPLACE FUNCTION public.pm_gere_clinique(p_profile_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (auth.jwt() ->> 'sub') IS NOT NULL AND p_profile_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM user_profiles up
    WHERE up.id = p_profile_id
      AND public.pm_acces_compte(up.uid, p_profile_id::text, ARRAY['vet_agenda'])
  );
$$;
GRANT EXECUTE ON FUNCTION public.pm_gere_clinique(uuid) TO anon, authenticated;

DROP POLICY IF EXISTS salles_clinique_select ON public.salles_clinique;
DROP POLICY IF EXISTS salles_clinique_write ON public.salles_clinique;
CREATE POLICY salles_clinique_select ON public.salles_clinique
  FOR SELECT USING (public.pm_gere_clinique(clinique_profile_id)
    OR public.pm_employe_profil(clinique_profile_id, ARRAY['vet_patients', 'vet_cr_rediger', 'vet_cr_valider']));
CREATE POLICY salles_clinique_write ON public.salles_clinique
  FOR ALL USING (public.pm_gere_clinique(clinique_profile_id))
  WITH CHECK (public.pm_gere_clinique(clinique_profile_id));

-- Motif → type de salle, ex. {"chirurgie":"chirurgie","bilan":"consultation"}.
-- Défaut (clé absente) : consultation. Visite à domicile : aucune salle.
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS salles_par_motif jsonb DEFAULT '{}'::jsonb;

-- ── Praticien d'un créneau / d'une indisponibilité, salle d'un RDV ──────
ALTER TABLE creneaux_pro  ADD COLUMN IF NOT EXISTS praticien_profile_id uuid REFERENCES user_profiles(id) ON DELETE CASCADE;
ALTER TABLE agenda_events ADD COLUMN IF NOT EXISTS praticien_profile_id uuid REFERENCES user_profiles(id) ON DELETE SET NULL;
ALTER TABLE rdv           ADD COLUMN IF NOT EXISTS salle_id uuid REFERENCES salles_clinique(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_rdv_profil_date ON public.rdv (pro_profile_id, date_heure);

-- Unicité d'un créneau : par PRATICIEN (deux vétérinaires de la même
-- clinique peuvent être disponibles à la même heure). NULLS NOT DISTINCT :
-- les créneaux du titulaire (praticien vide) restent uniques.
-- ⚠ Les upserts appli / site utilisent désormais
--   onConflict 'pro_uid,pro_profile_id,praticien_profile_id,date,heure_debut'
--   → déployer appli + site avec cette migration.
ALTER TABLE creneaux_pro DROP CONSTRAINT IF EXISTS creneaux_pro_uid_profile_date_heure_key;
ALTER TABLE creneaux_pro DROP CONSTRAINT IF EXISTS creneaux_pro_praticien_date_heure_key;
ALTER TABLE creneaux_pro ADD CONSTRAINT creneaux_pro_praticien_date_heure_key
  UNIQUE NULLS NOT DISTINCT (pro_uid, pro_profile_id, praticien_profile_id, date, heure_debut);

-- Créneaux : en plus du titulaire / cogérant, l'équipe « agenda » de CE
-- profil, et chaque praticien pour SES créneaux.
DROP POLICY IF EXISTS creneaux_pro_write ON public.creneaux_pro;
CREATE POLICY creneaux_pro_write ON public.creneaux_pro
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = creneaux_pro.pro_uid
               AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
    OR public.pm_employe_profil(nullif(pro_profile_id, '')::uuid, ARRAY['vet_agenda'])
    OR (praticien_profile_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM employes e WHERE e.eleveur_profile_id::text = creneaux_pro.pro_profile_id
            AND e.employe_profile_id = creneaux_pro.praticien_profile_id
            AND e.uid_employe = (auth.jwt() ->> 'sub') AND e.actif = true))
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = creneaux_pro.pro_uid
               AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
    OR public.pm_employe_profil(nullif(pro_profile_id, '')::uuid, ARRAY['vet_agenda'])
    OR (praticien_profile_id IS NOT NULL AND EXISTS (
          SELECT 1 FROM employes e WHERE e.eleveur_profile_id::text = creneaux_pro.pro_profile_id
            AND e.employe_profile_id = creneaux_pro.praticien_profile_id
            AND e.uid_employe = (auth.jwt() ->> 'sub') AND e.actif = true))
  );

-- ── Lecture publique (réservation) — aucune donnée personnelle ───────────
-- Plages occupées d'un profil pro : RDV actifs + indisponibilités.
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
     AND coalesce(e.date_fin, e.date_debut + interval '1 hour') > p_debut;
$$;
GRANT EXECUTE ON FUNCTION public.pm_plages_occupees(text, timestamptz, timestamptz) TO anon, authenticated;

-- Praticiens d'une clinique : titulaire (profil pro) + vétérinaires employés.
CREATE OR REPLACE FUNCTION public.pm_praticiens_clinique(p_pro_profile_id uuid)
RETURNS TABLE (praticien_profile_id uuid, nom text, avatar_url text, titulaire boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NULL::uuid,
         coalesce(nullif(trim(coalesce(up.firstname, '') || ' ' || coalesce(up.lastname, '')), ''), up.nom),
         up.avatar_url, true
    FROM user_profiles up WHERE up.id = p_pro_profile_id
  UNION ALL
  SELECT e.employe_profile_id,
         coalesce(nullif(trim(coalesce(ep.firstname, '') || ' ' || coalesce(ep.lastname, '')), ''), ep.nom, 'Vétérinaire'),
         ep.avatar_url, false
    FROM employes e JOIN user_profiles ep ON ep.id = e.employe_profile_id
   WHERE e.eleveur_profile_id = p_pro_profile_id AND e.actif = true AND e.role_pro = 'veterinaire';
$$;
GRANT EXECUTE ON FUNCTION public.pm_praticiens_clinique(uuid) TO anon, authenticated;

-- Salles actives d'une clinique (identifiant + type, sans plus).
CREATE OR REPLACE FUNCTION public.pm_salles_actives(p_pro_profile_id uuid)
RETURNS TABLE (id uuid, type_salle text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT s.id, s.type_salle FROM salles_clinique s
   WHERE s.clinique_profile_id = p_pro_profile_id AND s.actif = true
   ORDER BY s.ordre, s.created_at;
$$;
GRANT EXECUTE ON FUNCTION public.pm_salles_actives(uuid) TO anon, authenticated;

-- ── Contrôle à l'enregistrement d'un RDV vétérinaire ────────────────────
-- Motif (libellé saisi) → clé de motif (durees_motifs).
CREATE OR REPLACE FUNCTION public.pm_cle_motif(p_motif text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_motif IS NULL THEN 'autre'
    WHEN lower(p_motif) LIKE '%chirurg%' THEN 'chirurgie'
    WHEN lower(p_motif) LIKE '%vaccin%' THEN 'vaccination'
    WHEN lower(p_motif) LIKE '%urgen%' THEN 'urgence'
    WHEN lower(p_motif) LIKE '%bilan%' THEN 'bilan'
    WHEN lower(p_motif) LIKE '%domicile%' THEN 'visite_domicile'
    WHEN lower(p_motif) LIKE '%consult%' THEN 'consultation'
    ELSE 'autre' END;
$$;

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

  -- Une réservation à la fois par clinique (deux clients au même instant).
  PERFORM pg_advisory_xact_lock(hashtext('rdv_clinique_' || NEW.pro_profile_id));

  -- 1. Praticien déjà pris (RDV ou indisponibilité) → refus pour un client.
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

  -- 2. Salle : à domicile, aucune ; sinon une salle libre du type du motif.
  IF v_cle = 'visite_domicile' OR NEW.lieu_lat IS NOT NULL THEN
    NEW.salle_id := NULL;
    RETURN NEW;
  END IF;
  SELECT EXISTS (SELECT 1 FROM salles_clinique s WHERE s.clinique_profile_id::text = NEW.pro_profile_id AND s.actif)
    INTO v_a_salles;
  IF NOT v_a_salles THEN RETURN NEW; END IF;  -- cabinet sans salles déclarées

  SELECT coalesce(up.salles_par_motif ->> v_cle, 'consultation') INTO v_type_salle
    FROM user_profiles up WHERE up.id::text = NEW.pro_profile_id;

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
   ORDER BY s.ordre, s.created_at
   LIMIT 1;

  IF v_salle IS NULL THEN
    IF v_client THEN
      RAISE EXCEPTION 'Plus de salle disponible sur ce créneau. Choisissez-en un autre.' USING ERRCODE = 'P0001';
    END IF;
    -- Saisie du pro : enregistrée quand même (sans salle si celle demandée est prise).
    IF NEW.salle_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM salles_clinique WHERE id = NEW.salle_id) THEN
      NEW.salle_id := NULL;
    END IF;
    RETURN NEW;
  END IF;
  NEW.salle_id := v_salle;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_rdv_controle_clinique ON public.rdv;
CREATE TRIGGER trg_rdv_controle_clinique
  BEFORE INSERT OR UPDATE ON public.rdv
  FOR EACH ROW EXECUTE FUNCTION public.pm_rdv_controle_clinique();

COMMIT;

-- Nouvelle colonne publique de user_profiles : vue masquée + droits.
SELECT public.pm_recreer_vues_perso();
SELECT public.pm_appliquer_droits_perso();
