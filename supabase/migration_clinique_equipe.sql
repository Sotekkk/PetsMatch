-- ════════════════════════════════════════════════════════════════════════
-- Équipe vétérinaire (ASV + praticiens) — PHASE 1 : données et accès.
-- Décisions (07/10/2026) :
--   • l'employé (ASV ou vétérinaire praticien) travaille depuis SON compte,
--     via « Mes Employeurs » — même système que l'élevage : employes +
--     employe_permissions + pm_acces_compte ;
--   • un compte rendu rédigé par un ASV est un BROUILLON : seul un
--     vétérinaire (gérant, cogérant, ou employé avec vet_cr_valider) le
--     valide ; le propriétaire de l'animal ne voit que les CR validés ;
--   • fichier patients partagé dans la clinique.
--
-- MULTI-PROFIL : tout accès employé est limité au PROFIL de la clinique
-- (employes.eleveur_profile_id = pro_profile_id du RDV / CR / ordonnance /
-- accès animal) — jamais aux autres profils du gérant.
--
-- Droits (employe_permissions.permission) :
--   vet_agenda       gérer l'agenda de la clinique
--   vet_patients     voir les patients (fiches, carnets partagés à la clinique)
--   vet_cr_rediger   rédiger des comptes rendus (brouillons)
--   vet_cr_valider   valider / envoyer les comptes rendus
--   vet_ordonnances  rédiger des ordonnances (vétérinaire uniquement)
--
-- Idempotent. Staging d'abord (tests par rôle : scripts/staging/), puis prod.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── Rôle dans l'équipe ───────────────────────────────────────────────────
ALTER TABLE employes ADD COLUMN IF NOT EXISTS role_pro TEXT;
ALTER TABLE employes DROP CONSTRAINT IF EXISTS employes_role_pro_check;
ALTER TABLE employes ADD CONSTRAINT employes_role_pro_check
  CHECK (role_pro IS NULL OR role_pro IN ('asv', 'veterinaire'));

-- ── Comptes rendus : brouillon / validé, rédacteur, validateur ──────────
ALTER TABLE comptes_rendus
  ADD COLUMN IF NOT EXISTS statut                TEXT NOT NULL DEFAULT 'valide',
  ADD COLUMN IF NOT EXISTS redige_par_uid        TEXT,
  ADD COLUMN IF NOT EXISTS redige_par_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS valide_par_uid        TEXT,
  ADD COLUMN IF NOT EXISTS valide_par_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS valide_le             TIMESTAMPTZ;
ALTER TABLE comptes_rendus DROP CONSTRAINT IF EXISTS comptes_rendus_statut_check;
ALTER TABLE comptes_rendus ADD CONSTRAINT comptes_rendus_statut_check
  CHECK (statut IN ('brouillon', 'valide'));

-- ── Ordonnances : praticien prescripteur ─────────────────────────────────
ALTER TABLE ordonnances
  ADD COLUMN IF NOT EXISTS praticien_uid        TEXT,
  ADD COLUMN IF NOT EXISTS praticien_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

-- (rdv.instructeur_profile_id existe déjà : praticien / intervenant du RDV.)

-- ── Employé actif d'un PROFIL pro, avec l'un des droits ─────────────────
CREATE OR REPLACE FUNCTION public.pm_employe_profil(p_profile_id uuid, p_droits text[])
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (auth.jwt() ->> 'sub') IS NOT NULL AND p_profile_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM employes e
    JOIN employe_permissions ep
      ON ep.eleveur_profile_id = e.eleveur_profile_id
     AND ep.employe_profile_id = e.employe_profile_id
    WHERE e.eleveur_profile_id = p_profile_id
      AND e.uid_employe = (auth.jwt() ->> 'sub')
      AND e.actif = true
      AND ep.permission = ANY (p_droits)
  );
$$;
GRANT EXECUTE ON FUNCTION public.pm_employe_profil(uuid, text[]) TO anon, authenticated;

-- ── Patients : accès animal accordé à la clinique → ses employés ────────
CREATE OR REPLACE FUNCTION public.has_animal_access(p_animal_id text, p_uid text, p_require_write boolean DEFAULT false)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM animal_access aa
    JOIN user_profiles up ON up.id = aa.pro_profile_id
    WHERE aa.animal_id = p_animal_id
      AND (
        up.uid = p_uid
        -- Employé de CE profil pro (clinique) avec le droit « patients ».
        OR EXISTS (
          SELECT 1 FROM employes e
          JOIN employe_permissions ep
            ON ep.eleveur_profile_id = e.eleveur_profile_id
           AND ep.employe_profile_id = e.employe_profile_id
          WHERE e.eleveur_profile_id = aa.pro_profile_id
            AND e.uid_employe = p_uid AND e.actif = true
            AND ep.permission = 'vet_patients'
        )
      )
      AND (
        aa.statut = 'active_write'
        OR (aa.statut = 'active'
            AND (NOT p_require_write
                 OR up.profile_type IN ('veterinaire', 'sante', 'marechal_ferrant')))
      )
  );
$function$;

-- Liste des accès (fichier patients de la clinique) lisible par l'équipe.
DROP POLICY IF EXISTS animal_access_equipe_select ON public.animal_access;
CREATE POLICY animal_access_equipe_select ON public.animal_access
  FOR SELECT USING (public.pm_employe_profil(pro_profile_id, ARRAY['vet_patients']));

-- ── Comptes rendus ───────────────────────────────────────────────────────
-- Lecture : la clinique (gérant, cogérant, équipe) voit tout, brouillons
-- compris ; le propriétaire de l'animal ne voit que les CR validés.
DROP POLICY IF EXISTS comptes_rendus_select ON public.comptes_rendus;
CREATE POLICY comptes_rendus_select ON public.comptes_rendus
  FOR SELECT USING (
    public.pm_acces_compte(pro_uid, coalesce(pro_profile_id::text, ''),
      ARRAY['vet_patients', 'vet_cr_rediger', 'vet_cr_valider'])
    OR (statut = 'valide' AND public.can_access_pro_document(
      animal_id, owner_uid, owner_profile_id, pro_uid, pro_profile_id, (auth.jwt() ->> 'sub')))
  );

DROP POLICY IF EXISTS comptes_rendus_write ON public.comptes_rendus;
DROP POLICY IF EXISTS comptes_rendus_insert ON public.comptes_rendus;
DROP POLICY IF EXISTS comptes_rendus_update ON public.comptes_rendus;
DROP POLICY IF EXISTS comptes_rendus_delete ON public.comptes_rendus;
CREATE POLICY comptes_rendus_insert ON public.comptes_rendus
  FOR INSERT WITH CHECK (public.pm_acces_compte(pro_uid, coalesce(pro_profile_id::text, ''),
    ARRAY['vet_cr_rediger', 'vet_cr_valider']));
CREATE POLICY comptes_rendus_update ON public.comptes_rendus
  FOR UPDATE USING (public.pm_acces_compte(pro_uid, coalesce(pro_profile_id::text, ''),
    ARRAY['vet_cr_rediger', 'vet_cr_valider']))
  WITH CHECK (public.pm_acces_compte(pro_uid, coalesce(pro_profile_id::text, ''),
    ARRAY['vet_cr_rediger', 'vet_cr_valider']));
-- Suppression : un validé seulement par qui peut valider ; un brouillon
-- aussi par l'équipe qui rédige.
CREATE POLICY comptes_rendus_delete ON public.comptes_rendus
  FOR DELETE USING (
    public.pm_acces_compte(pro_uid, coalesce(pro_profile_id::text, ''), ARRAY['vet_cr_valider'])
    OR (statut = 'brouillon' AND public.pm_acces_compte(pro_uid, coalesce(pro_profile_id::text, ''),
      ARRAY['vet_cr_rediger']))
  );

-- Validation réservée au vétérinaire : sans le droit, l'écriture reste un
-- brouillon et un CR déjà validé ne se modifie plus. Rédacteur / validateur
-- horodatés côté serveur. (service_role : pas de jeton → inchangé.)
CREATE OR REPLACE FUNCTION public.pm_cr_controle_validation()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub  text := auth.jwt() ->> 'sub';
  v_peut boolean;
BEGIN
  IF v_sub IS NULL THEN RETURN NEW; END IF;
  -- Titulaire / cogérant : toujours ; employé : droit vet_cr_valider.
  v_peut := public.pm_acces_compte(NEW.pro_uid, coalesce(NEW.pro_profile_id::text, ''), ARRAY['vet_cr_valider']);
  IF TG_OP = 'INSERT' AND NEW.redige_par_uid IS NULL THEN
    NEW.redige_par_uid := v_sub;
  END IF;
  IF NOT v_peut THEN
    IF TG_OP = 'UPDATE' AND OLD.statut = 'valide' THEN
      RAISE EXCEPTION 'Compte rendu déjà validé : modification réservée au vétérinaire'
        USING ERRCODE = '42501';
    END IF;
    NEW.statut := 'brouillon';
    NEW.valide_par_uid := NULL;
    NEW.valide_par_profile_id := NULL;
    NEW.valide_le := NULL;
  ELSIF NEW.statut = 'valide' AND (TG_OP = 'INSERT' OR OLD.statut IS DISTINCT FROM 'valide') THEN
    NEW.valide_par_uid := v_sub;
    NEW.valide_le := now();
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_cr_controle_validation ON public.comptes_rendus;
CREATE TRIGGER trg_cr_controle_validation
  BEFORE INSERT OR UPDATE ON public.comptes_rendus
  FOR EACH ROW EXECUTE FUNCTION public.pm_cr_controle_validation();

-- ── Ordonnances : prescription = vétérinaire (gérant, cogérant, praticien
-- avec vet_ordonnances) ; lecture aussi pour l'équipe « patients ».
DROP POLICY IF EXISTS ordonnances_select ON public.ordonnances;
CREATE POLICY ordonnances_select ON public.ordonnances
  FOR SELECT USING (
    public.pm_acces_compte(pro_uid, coalesce(pro_profile_id::text, ''), ARRAY['vet_patients', 'vet_ordonnances'])
    OR public.can_access_pro_document(animal_id, owner_uid, owner_profile_id, pro_uid, pro_profile_id, (auth.jwt() ->> 'sub'))
  );
DROP POLICY IF EXISTS ordonnances_write ON public.ordonnances;
CREATE POLICY ordonnances_write ON public.ordonnances
  FOR ALL USING (public.pm_acces_compte(pro_uid, coalesce(pro_profile_id::text, ''), ARRAY['vet_ordonnances']))
  WITH CHECK (public.pm_acces_compte(pro_uid, coalesce(pro_profile_id::text, ''), ARRAY['vet_ordonnances']));

NOTIFY pgrst, 'reload schema';

COMMIT;
