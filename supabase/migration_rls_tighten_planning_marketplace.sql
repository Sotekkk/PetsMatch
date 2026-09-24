-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 38/N : module Planning (protocoles) + tarifs +
--   marketplace + subscriptions (legacy)
--   plan_templates, plans_actifs, plan_template_etapes,
--   plan_template_autorisations, plans_tarifaires, marketplace_ads,
--   marketplace_partners, subscriptions
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- plan_templates / plans_actifs / plan_template_etapes (module Planning —
-- protocoles de soins/rappels) : jamais protégés. Accès élevage/cogérant +
-- employé actif ; écriture (créer/modifier un protocole) réservée à
-- l'éleveur/cogérant + employé ayant la permission `write_protocoles`, OU
-- spécifiquement autorisé sur CE template précis via
-- plan_template_autorisations (confirmé dans plan_template_list_page.dart :
-- « un employé ne peut appliquer que ses propres protocoles, sauf
-- autorisation explicite »).
--
-- plan_template_autorisations (qui peut appliquer quel protocole) :
-- lecture par l'éleveur/cogérant (gestion) ET par l'employé concerné
-- lui-même (il consulte ses propres autorisations) ; écriture réservée à
-- l'éleveur/cogérant (c'est lui qui accorde/révoque).
--
-- plans_tarifaires (catalogue de prix) : lecture publique (affiché avant
-- inscription), écriture jamais côté client (toujours via
-- api/admin/tarification, clé service_role) — verrouillé à l'admin par
-- sécurité.
--
-- marketplace_partners : lecture publique (CTA assurance affiché à tout
-- particulier, animal_fiche_particulier.dart), écriture partenaire
-- (user_id) + admin.
--
-- marketplace_ads : aucune lecture côté client trouvée (pas de back-office
-- dédié dans le code actuel) — verrouillé au partenaire concerné + admin.
--
-- subscriptions : table historique (migration Firestore → Supabase, cf.
-- supabase_migration_page.dart) — la source de vérité des abonnements est
-- `abonnements`, jamais cette table côté fonctionnalités actuelles.
-- Verrouillée par sécurité (uid), sans impact fonctionnel connu.
--
-- ⚠️ À TESTER après exécution :
--   1. Le module Planning (créer un protocole, l'appliquer, voir les
--      étapes) fonctionne pour l'éleveur/cogérant.
--   2. Un employé avec la permission « Créer des protocoles » peut créer
--      les siens ; un employé spécifiquement autorisé sur un protocole
--      d'un collègue peut l'appliquer.
--   3. Gérer les autorisations d'un protocole (accorder/révoquer) fonctionne
--      pour l'éleveur.
--   4. Les tarifs restent visibles publiquement ; le CTA assurance
--      s'affiche toujours sur la fiche animal particulier.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── Fonction : accès au module Planning d'un éleveur ──────────────────────
CREATE OR REPLACE FUNCTION public.can_access_planning(
  p_uid_eleveur   TEXT,
  p_uid           TEXT,
  p_require_write BOOLEAN DEFAULT false,
  p_template_id   UUID DEFAULT NULL
)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT p_uid_eleveur = p_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = p_uid_eleveur AND c.uid_cogerant = p_uid AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR EXISTS (
      SELECT 1 FROM employes e
      WHERE e.uid_eleveur = p_uid_eleveur AND e.uid_employe = p_uid AND e.actif = true
        AND (
          NOT p_require_write
          OR EXISTS (
            SELECT 1 FROM employe_permissions ep
            WHERE ep.eleveur_profile_id = e.eleveur_profile_id
              AND ep.employe_profile_id = e.employe_profile_id
              AND ep.permission = 'write_protocoles'
          )
          OR (p_template_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM plan_template_autorisations pta
            WHERE pta.template_id = p_template_id AND pta.employe_profile_id = e.employe_profile_id
          ))
        )
    );
$$;
GRANT EXECUTE ON FUNCTION public.can_access_planning(TEXT, TEXT, BOOLEAN, UUID) TO anon, authenticated;

-- ── plan_templates ──────────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE plan_templates ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'plan_templates'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.plan_templates', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "plan_templates_select" ON plan_templates
  FOR SELECT USING (public.can_access_planning(uid_eleveur, (auth.jwt() ->> 'sub'), false, id));
CREATE POLICY "plan_templates_insert" ON plan_templates
  FOR INSERT WITH CHECK (public.can_access_planning(uid_eleveur, (auth.jwt() ->> 'sub'), true, NULL));
CREATE POLICY "plan_templates_update" ON plan_templates
  FOR UPDATE USING (public.can_access_planning(uid_eleveur, (auth.jwt() ->> 'sub'), true, id))
  WITH CHECK (public.can_access_planning(uid_eleveur, (auth.jwt() ->> 'sub'), true, id));
CREATE POLICY "plan_templates_delete" ON plan_templates
  FOR DELETE USING (public.can_access_planning(uid_eleveur, (auth.jwt() ->> 'sub'), true, id));

-- ── plans_actifs (instances appliquées d'un template) ─────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE plans_actifs ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'plans_actifs'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.plans_actifs', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "plans_actifs_select" ON plans_actifs
  FOR SELECT USING (public.can_access_planning(uid_eleveur, (auth.jwt() ->> 'sub'), false, template_id));
CREATE POLICY "plans_actifs_write" ON plans_actifs
  FOR ALL USING (public.can_access_planning(uid_eleveur, (auth.jwt() ->> 'sub'), true, template_id))
  WITH CHECK (public.can_access_planning(uid_eleveur, (auth.jwt() ->> 'sub'), true, template_id));

-- ── plan_template_etapes (étapes, rattachées via template_id) ────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE plan_template_etapes ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'plan_template_etapes'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.plan_template_etapes', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "plan_template_etapes_select" ON plan_template_etapes
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM plan_templates t
      WHERE t.id = plan_template_etapes.template_id
        AND public.can_access_planning(t.uid_eleveur, (auth.jwt() ->> 'sub'), false, t.id)
    )
  );
CREATE POLICY "plan_template_etapes_write" ON plan_template_etapes
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM plan_templates t
      WHERE t.id = plan_template_etapes.template_id
        AND public.can_access_planning(t.uid_eleveur, (auth.jwt() ->> 'sub'), true, t.id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM plan_templates t
      WHERE t.id = plan_template_etapes.template_id
        AND public.can_access_planning(t.uid_eleveur, (auth.jwt() ->> 'sub'), true, t.id)
    )
  );

-- ── plan_template_autorisations (gestion = propriétaire, lecture aussi par l'employé concerné) ──
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE plan_template_autorisations ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'plan_template_autorisations'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.plan_template_autorisations', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "plan_template_autorisations_select" ON plan_template_autorisations
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM user_profiles up WHERE up.id = plan_template_autorisations.employe_profile_id AND up.uid = (auth.jwt() ->> 'sub'))
    OR EXISTS (
      SELECT 1 FROM plan_templates t
      WHERE t.id = plan_template_autorisations.template_id
        AND public.can_access_planning(t.uid_eleveur, (auth.jwt() ->> 'sub'), true, t.id)
    )
  );
CREATE POLICY "plan_template_autorisations_write" ON plan_template_autorisations
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM plan_templates t
      WHERE t.id = plan_template_autorisations.template_id
        AND public.can_access_planning(t.uid_eleveur, (auth.jwt() ->> 'sub'), true, t.id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM plan_templates t
      WHERE t.id = plan_template_autorisations.template_id
        AND public.can_access_planning(t.uid_eleveur, (auth.jwt() ->> 'sub'), true, t.id)
    )
  );

-- ── plans_tarifaires (catalogue public, écriture admin) ────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE plans_tarifaires ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'plans_tarifaires'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.plans_tarifaires', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "plans_tarifaires_select" ON plans_tarifaires FOR SELECT USING (true);
CREATE POLICY "plans_tarifaires_write" ON plans_tarifaires
  FOR ALL USING (public.is_admin_uid((auth.jwt() ->> 'sub')))
  WITH CHECK (public.is_admin_uid((auth.jwt() ->> 'sub')));

-- ── marketplace_partners (annuaire public, écriture partenaire/admin) ─────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE marketplace_partners ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'marketplace_partners'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.marketplace_partners', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "marketplace_partners_select" ON marketplace_partners FOR SELECT USING (true);
CREATE POLICY "marketplace_partners_write" ON marketplace_partners
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = user_id OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = user_id OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );

-- ── marketplace_ads (jamais lu côté client, partenaire + admin) ──────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE marketplace_ads ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'marketplace_ads'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.marketplace_ads', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "marketplace_ads_all" ON marketplace_ads
  FOR ALL USING (
    public.is_admin_uid((auth.jwt() ->> 'sub'))
    OR EXISTS (SELECT 1 FROM marketplace_partners p WHERE p.id = marketplace_ads.partner_id AND p.user_id = (auth.jwt() ->> 'sub'))
  )
  WITH CHECK (
    public.is_admin_uid((auth.jwt() ->> 'sub'))
    OR EXISTS (SELECT 1 FROM marketplace_partners p WHERE p.id = marketplace_ads.partner_id AND p.user_id = (auth.jwt() ->> 'sub'))
  );

-- ── subscriptions (table historique, aucune fonctionnalité actuelle) ──────
DO $$
DECLARE pol RECORD;
BEGIN
  IF to_regclass('public.subscriptions') IS NULL THEN RETURN; END IF;
  ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'subscriptions'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.subscriptions', pol.policyname);
  END LOOP;
  EXECUTE $p$
    CREATE POLICY "subscriptions_owner" ON subscriptions
      FOR ALL USING ((auth.jwt() ->> 'sub') = uid)
      WITH CHECK ((auth.jwt() ->> 'sub') = uid)
  $p$;
END $$;

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN (
  'plan_templates','plans_actifs','plan_template_etapes','plan_template_autorisations',
  'plans_tarifaires','marketplace_partners','marketplace_ads','subscriptions'
)
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN (
--       'plan_templates','plans_actifs','plan_template_etapes','plan_template_autorisations',
--       'plans_tarifaires','marketplace_partners','marketplace_ads','subscriptions'
--     )
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- ALTER TABLE plan_templates DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE plans_actifs DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE plan_template_etapes DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE plan_template_autorisations DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE plans_tarifaires DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE marketplace_partners DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE marketplace_ads DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE subscriptions DISABLE ROW LEVEL SECURITY;
