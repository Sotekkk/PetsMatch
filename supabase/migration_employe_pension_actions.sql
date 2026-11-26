-- ══════════════════════════════════════════════════════════════════════════
-- Employé d'une pension : actions selon ses autorisations (26/11/2026)
-- ══════════════════════════════════════════════════════════════════════════
-- Nouvelles autorisations (employe_permissions.permission), données par la
-- pension dans « Mes employés » :
--   pension_arrivees_sorties : enregistrer l'arrivée et le départ d'un séjour
--                              (+ protocoles de séjour posés / retirés)
--   pension_nouvelles        : envoyer des nouvelles (note, photo, vidéo) au
--                              propriétaire (pension_updates)
--   pension_logements        : changer un pensionnaire de logement
--   pension_consignes        : compléter les consignes du séjour
-- Jusqu'ici un employé ne pouvait que LIRE le registre (read_planning_pension,
-- migration_rls_fix_employe_pension_protocoles.sql).
--
-- Scopé par PROFIL : l'autorisation doit venir du profil pension du séjour
-- (pension_entrees.pro_profile_id = employes.eleveur_profile_id), jamais
-- d'un autre profil du même employeur (ex. son élevage). Séjours anciens sans
-- pro_profile_id : règle par uid (employes.uid_eleveur = pro_uid).
--
-- pension_entrees : l'employé n'écrit QUE les colonnes de l'action autorisée
-- (trigger), quelles que soient les requêtes de l'appli.
--
-- À passer d'abord sur le staging (tests par rôle), puis en prod.
-- ══════════════════════════════════════════════════════════════════════════

-- ── 1) Autorisation d'un employé pour le profil pension d'un séjour ────────
CREATE OR REPLACE FUNCTION public.employe_pension_peut(
  p_pro_profile_id TEXT, p_pro_uid TEXT, p_employe_uid TEXT, p_permission TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT p_employe_uid IS NOT NULL AND EXISTS (
    SELECT 1 FROM employes e
    JOIN employe_permissions ep
      ON ep.eleveur_profile_id = e.eleveur_profile_id
     AND ep.employe_profile_id = e.employe_profile_id
    WHERE e.uid_employe = p_employe_uid
      AND e.actif = true
      AND ep.permission = p_permission
      AND (
        (COALESCE(p_pro_profile_id, '') <> '' AND e.eleveur_profile_id::text = p_pro_profile_id)
        OR (COALESCE(p_pro_profile_id, '') = '' AND e.uid_eleveur = p_pro_uid)
      )
  );
$$;
GRANT EXECUTE ON FUNCTION public.employe_pension_peut(TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;

-- Même contrôle à partir d'un séjour (lu sans les droits du visiteur), pour
-- les tables rattachées à un séjour (pension_updates).
CREATE OR REPLACE FUNCTION public.employe_pension_sejour_peut(
  p_entree_id UUID, p_pro_uid TEXT, p_employe_uid TEXT, p_permission TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM pension_entrees pe
    WHERE pe.id = p_entree_id
      AND (p_pro_uid IS NULL OR pe.pro_uid = p_pro_uid)
      AND public.employe_pension_peut(pe.pro_profile_id::text, pe.pro_uid, p_employe_uid, p_permission)
  );
$$;
GRANT EXECUTE ON FUNCTION public.employe_pension_sejour_peut(UUID, TEXT, TEXT, TEXT) TO anon, authenticated;

-- ── 2) pension_entrees : mise à jour par l'employé autorisé ────────────────
DROP POLICY IF EXISTS "pension_entrees_employe_actions" ON pension_entrees;
CREATE POLICY "pension_entrees_employe_actions" ON pension_entrees
  FOR UPDATE
  USING (
    public.employe_pension_peut(pro_profile_id::text, pro_uid, (auth.jwt() ->> 'sub'), 'pension_arrivees_sorties')
    OR public.employe_pension_peut(pro_profile_id::text, pro_uid, (auth.jwt() ->> 'sub'), 'pension_logements')
    OR public.employe_pension_peut(pro_profile_id::text, pro_uid, (auth.jwt() ->> 'sub'), 'pension_consignes')
  )
  WITH CHECK (
    public.employe_pension_peut(pro_profile_id::text, pro_uid, (auth.jwt() ->> 'sub'), 'pension_arrivees_sorties')
    OR public.employe_pension_peut(pro_profile_id::text, pro_uid, (auth.jwt() ->> 'sub'), 'pension_logements')
    OR public.employe_pension_peut(pro_profile_id::text, pro_uid, (auth.jwt() ->> 'sub'), 'pension_consignes')
  );

-- Colonnes modifiables par un employé, selon ses autorisations. La pension,
-- ses cogérants et le serveur (pas de jeton) ne sont pas concernés.
CREATE OR REPLACE FUNCTION public.pension_entrees_controle_employe()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub TEXT := auth.jwt() ->> 'sub';
  v_arr BOOLEAN; v_log BOOLEAN; v_cons BOOLEAN;
  v_cle TEXT;
  v_new JSONB := to_jsonb(NEW);
  v_old JSONB := to_jsonb(OLD);
BEGIN
  IF v_sub IS NULL OR v_sub = OLD.pro_uid THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = OLD.pro_uid AND c.uid_cogerant = v_sub
             AND c.statut = 'actif' AND c.date_fin IS NULL) THEN
    RETURN NEW;
  END IF;
  v_arr  := public.employe_pension_peut(OLD.pro_profile_id::text, OLD.pro_uid, v_sub, 'pension_arrivees_sorties');
  v_log  := public.employe_pension_peut(OLD.pro_profile_id::text, OLD.pro_uid, v_sub, 'pension_logements');
  v_cons := public.employe_pension_peut(OLD.pro_profile_id::text, OLD.pro_uid, v_sub, 'pension_consignes');
  -- Le séjour reste celui de la pension.
  IF NEW.pro_uid IS DISTINCT FROM OLD.pro_uid OR NEW.pro_profile_id IS DISTINCT FROM OLD.pro_profile_id THEN
    RAISE EXCEPTION 'Modification non autorisée pour un employé' USING ERRCODE = '42501';
  END IF;
  FOR v_cle IN SELECT key FROM jsonb_object_keys(v_new) AS key LOOP
    CONTINUE WHEN (v_new -> v_cle) IS NOT DISTINCT FROM (v_old -> v_cle);
    CONTINUE WHEN v_cle IN ('updated_at');
    IF v_cle IN ('statut', 'arrivee_reelle_le', 'depart_reel_le', 'date_sortie_effective', 'depose_par',
                 'recupere_par', 'effets_personnels', 'observations_arrivee', 'observations_depart') AND v_arr THEN
      -- Arrivée / départ : seulement « en pension » ↔ « sorti ».
      IF v_cle = 'statut' AND NEW.statut NOT IN ('en_pension', 'sorti') THEN
        RAISE EXCEPTION 'Statut non autorisé pour un employé' USING ERRCODE = '42501';
      END IF;
      CONTINUE;
    END IF;
    CONTINUE WHEN v_cle = 'logement_id' AND (v_log OR v_arr);
    CONTINUE WHEN v_cle = 'consignes_sejour' AND (v_cons OR v_arr);
    RAISE EXCEPTION 'Modification de « % » non autorisée pour un employé', v_cle USING ERRCODE = '42501';
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pension_entrees_controle_employe ON pension_entrees;
CREATE TRIGGER trg_pension_entrees_controle_employe
  BEFORE UPDATE ON pension_entrees
  FOR EACH ROW EXECUTE FUNCTION public.pension_entrees_controle_employe();

-- ── 3) pension_updates : nouvelles envoyées par l'employé ──────────────────
-- Lecture du journal : employé « Planning pension » ou « Nouvelles ».
DROP POLICY IF EXISTS "pension_updates_employe_select" ON pension_updates;
CREATE POLICY "pension_updates_employe_select" ON pension_updates
  FOR SELECT USING (
    public.employe_pension_sejour_peut(pension_entree_id, NULL, (auth.jwt() ->> 'sub'), 'read_planning_pension')
    OR public.employe_pension_sejour_peut(pension_entree_id, NULL, (auth.jwt() ->> 'sub'), 'pension_nouvelles')
  );

-- Envoi : rattaché à un séjour de la pension, au nom de la pension (pro_uid).
DROP POLICY IF EXISTS "pension_updates_employe_insert" ON pension_updates;
CREATE POLICY "pension_updates_employe_insert" ON pension_updates
  FOR INSERT WITH CHECK (
    public.employe_pension_sejour_peut(pension_entree_id, pro_uid, (auth.jwt() ->> 'sub'), 'pension_nouvelles')
  );

-- ── 4) Protocoles de séjour posés / retirés par l'employé (arrivée, départ) ─
-- Insertion des tâches : déjà ouverte aux employés actifs (plan_taches_related_insert).
DROP POLICY IF EXISTS "plans_actifs_employe_sejour" ON plans_actifs;
CREATE POLICY "plans_actifs_employe_sejour" ON plans_actifs
  FOR INSERT WITH CHECK (
    type_declencheur = 'sejour' AND profil_source = 'pension'
    AND public.employe_pension_peut(eleveur_profile_id::text, uid_eleveur, (auth.jwt() ->> 'sub'), 'pension_arrivees_sorties')
  );

DROP POLICY IF EXISTS "plan_taches_employe_sejour_update" ON plan_taches;
CREATE POLICY "plan_taches_employe_sejour_update" ON plan_taches
  FOR UPDATE USING (
    pension_entree_id IS NOT NULL
    AND public.employe_pension_peut(eleveur_profile_id::text, uid_eleveur, (auth.jwt() ->> 'sub'), 'pension_arrivees_sorties')
  )
  WITH CHECK (
    pension_entree_id IS NOT NULL
    AND public.employe_pension_peut(eleveur_profile_id::text, uid_eleveur, (auth.jwt() ->> 'sub'), 'pension_arrivees_sorties')
  );

DROP POLICY IF EXISTS "plan_taches_employe_sejour_delete" ON plan_taches;
CREATE POLICY "plan_taches_employe_sejour_delete" ON plan_taches
  FOR DELETE USING (
    pension_entree_id IS NOT NULL AND statut <> 'fait'
    AND public.employe_pension_peut(eleveur_profile_id::text, uid_eleveur, (auth.jwt() ->> 'sub'), 'pension_arrivees_sorties')
  );

-- ── 5) Logements de la pension : lecture par l'employé « Planning pension » ─
-- Sans elle, le planning de l'employé est vide et aucun logement n'est
-- proposé à l'arrivée. Logements de CE profil pension (profile_id), sinon
-- (anciens logements sans profil) ceux du compte de la pension.
DROP POLICY IF EXISTS "enclos_chenil_employe_pension_select" ON enclos_chenil;
CREATE POLICY "enclos_chenil_employe_pension_select" ON enclos_chenil
  FOR SELECT USING (
    public.employe_pension_peut(profile_id::text, uid_eleveur, (auth.jwt() ->> 'sub'), 'read_planning_pension')
  );

NOTIFY pgrst, 'reload schema';

-- ── Vérification ───────────────────────────────────────────────────────────
SELECT tablename, policyname, cmd FROM pg_policies
WHERE policyname IN ('pension_entrees_employe_actions', 'pension_updates_employe_select', 'pension_updates_employe_insert',
                     'plans_actifs_employe_sejour', 'plan_taches_employe_sejour_update', 'plan_taches_employe_sejour_delete',
                     'enclos_chenil_employe_pension_select')
ORDER BY tablename, policyname;

-- ── Retour arrière ─────────────────────────────────────────────────────────
-- DROP TRIGGER IF EXISTS trg_pension_entrees_controle_employe ON pension_entrees;
-- DROP FUNCTION IF EXISTS public.pension_entrees_controle_employe();
-- DROP POLICY IF EXISTS "pension_entrees_employe_actions" ON pension_entrees;
-- DROP POLICY IF EXISTS "pension_updates_employe_select" ON pension_updates;
-- DROP POLICY IF EXISTS "pension_updates_employe_insert" ON pension_updates;
-- DROP POLICY IF EXISTS "plans_actifs_employe_sejour" ON plans_actifs;
-- DROP POLICY IF EXISTS "plan_taches_employe_sejour_update" ON plan_taches;
-- DROP POLICY IF EXISTS "plan_taches_employe_sejour_delete" ON plan_taches;
-- DROP POLICY IF EXISTS "enclos_chenil_employe_pension_select" ON enclos_chenil;
-- DROP FUNCTION IF EXISTS public.employe_pension_sejour_peut(UUID, TEXT, TEXT, TEXT);
-- DROP FUNCTION IF EXISTS public.employe_pension_peut(TEXT, TEXT, TEXT, TEXT);
