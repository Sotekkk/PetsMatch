-- ══════════════════════════════════════════════════════════════════════════
-- Accès employé — 2 trous du même genre que migration_rls_fix_employe_write_animaux.sql
-- ══════════════════════════════════════════════════════════════════════════
-- Suite au signalement : les employés (toutes catégories pro confondues,
-- pas seulement éleveur) avaient perdu des droits après le durcissement RLS
-- (vagues 1 à 40/N). Audit de toutes les tables où un employé intervient
-- (carnet de santé, repro, inventaire, protocoles, pension, association…) :
-- la plupart sont correctes (can_access_animal_health, can_access_animal_repro,
-- can_access_inventaire, can_access_planning incluent déjà la bonne branche
-- employé). Deux trous confirmés, même famille que le bug animaux :
--
-- 1) plan_taches (vague 7/N, migration_rls_tighten_taches.sql) : le
--    commentaire d'origine du fichier annonçait explicitement « INSERT : le
--    propriétaire, un cogérant actif, OU un employé actif de cet élevage »
--    — implémenté pour taches_elevage, mais OUBLIÉ pour plan_taches (la
--    policy réelle ne contenait que propriétaire + cogérant). Conséquence
--    concrète : quand un employé avec la permission « Créer des protocoles »
--    (write_protocoles) crée ou applique son propre protocole
--    (plan_template_form_page.dart / plan_template_list_page.dart,
--    PlanningService.applyTemplate), les tâches générées automatiquement
--    (plan_taches) échouent à l'insertion — c'est le bug « faire des
--    protocole » rapporté.
--
-- 2) pension_entrees, pension_nettoyages (vague 18/N,
--    migration_rls_tighten_pension_garde.sql) : n'incluaient AUCUNE notion
--    d'employé (seulement pro_uid/uid_eleveur + cogérant actif), alors que
--    la permission dédiée 'read_planning_pension' (« Voir le planning
--    d'occupation et les fiches des animaux en pension ») existe côté appli
--    précisément pour ça : un employé pension ouvre PensionPlanningPage
--    depuis Mes Employeurs (employes_page.dart, bouton « 📅 Planning »,
--    gated par perms.contains('read_planning_pension')), qui interroge ces
--    2 tables filtrées sur l'uid de l'EMPLOYEUR — jusqu'ici bloqué par RLS.
--    Cette vue est en lecture seule côté employé (_readOnly = employerUid
--    != null dans pension_planning_page.dart, aucune écriture déclenchée) :
--    SELECT seul suffit, l'écriture pro/cogérant existante reste inchangée.
--
-- Réutilise public.employe_has_permission(p_eleveur_uid, p_employe_uid,
-- p_permission), créée par migration_rls_fix_employe_write_animaux.sql —
-- redéfinie ici aussi (CREATE OR REPLACE, identique) pour que ce fichier
-- soit exécutable indépendamment.
--
-- Autres tables pension (cles_clients, tarifs_clients_garde,
-- pension_updates, pension_factures) et association (familles_accueil,
-- petfriends, reservations_animaux, protocoles_chaleur_race) : vérifiées,
-- AUCUN écran employé ne les interroge actuellement (recherche
-- « employerUid » dans lib/ : seuls pension_planning_page.dart,
-- plan_template_form_page.dart et plan_template_list_page.dart acceptent ce
-- paramètre) — laissées pro/cogérant uniquement, conforme au comportement
-- actuel de l'appli. À revisiter seulement si un futur écran employé les
-- expose.
--
-- ⚠️ À TESTER après exécution :
--   1. Un employé avec la permission « Créer des protocoles » peut créer
--      et appliquer un protocole : le template ET les tâches générées
--      (agenda / Mes Employés → Tâches) apparaissent bien.
--   2. Un employé pension avec la permission « Planning pension »
--      (read_planning_pension) voit le planning d'occupation et les
--      nettoyages depuis Mes Employeurs → 📅 Planning.
--   3. Un employé SANS ces permissions reste bloqué comme avant.
--   4. Le gérant, un cogérant actif, continuent de fonctionner normalement
--      partout (aucune policy existante modifiée en retrait de droits).
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.employe_has_permission(p_eleveur_uid TEXT, p_employe_uid TEXT, p_permission TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM employes e
    JOIN employe_permissions ep
      ON ep.eleveur_profile_id = e.eleveur_profile_id
     AND ep.employe_profile_id = e.employe_profile_id
    WHERE e.uid_eleveur = p_eleveur_uid
      AND e.uid_employe = p_employe_uid
      AND e.actif = true
      AND ep.permission = p_permission
  );
$$;
GRANT EXECUTE ON FUNCTION public.employe_has_permission(TEXT, TEXT, TEXT) TO anon, authenticated;

-- ── 1) plan_taches : ajout de la branche employé actif à l'INSERT ─────────
DROP POLICY IF EXISTS "plan_taches_related_insert" ON plan_taches;

CREATE POLICY "plan_taches_related_insert" ON plan_taches
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = plan_taches.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR EXISTS (
      SELECT 1 FROM employes e
      WHERE e.uid_eleveur = plan_taches.uid_eleveur
        AND e.uid_employe = (auth.jwt() ->> 'sub')
        AND e.actif = true
    )
  );

-- ── 2) pension_entrees / pension_nettoyages : lecture employé « read_planning_pension » ──
-- Policies additives (FOR SELECT), en OR avec les policies FOR ALL
-- pro/cogérant existantes — n'ouvre AUCUNE écriture.
DROP POLICY IF EXISTS "pension_entrees_employe_read_planning" ON pension_entrees;
CREATE POLICY "pension_entrees_employe_read_planning" ON pension_entrees
  FOR SELECT USING (
    public.employe_has_permission(pro_uid, (auth.jwt() ->> 'sub'), 'read_planning_pension')
  );

DROP POLICY IF EXISTS "pension_nettoyages_employe_read_planning" ON pension_nettoyages;
CREATE POLICY "pension_nettoyages_employe_read_planning" ON pension_nettoyages
  FOR SELECT USING (
    public.employe_has_permission(uid_eleveur, (auth.jwt() ->> 'sub'), 'read_planning_pension')
  );

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('plan_taches','pension_entrees','pension_nettoyages')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "plan_taches_related_insert" ON plan_taches;
-- CREATE POLICY "plan_taches_related_insert" ON plan_taches
--   FOR INSERT WITH CHECK (
--     (auth.jwt() ->> 'sub') = uid_eleveur
--     OR EXISTS (
--       SELECT 1 FROM elevage_cogerants c
--       WHERE c.uid_gerant = plan_taches.uid_eleveur
--         AND c.uid_cogerant = (auth.jwt() ->> 'sub')
--         AND c.statut = 'actif' AND c.date_fin IS NULL
--     )
--   );
-- DROP POLICY IF EXISTS "pension_entrees_employe_read_planning" ON pension_entrees;
-- DROP POLICY IF EXISTS "pension_nettoyages_employe_read_planning" ON pension_nettoyages;
