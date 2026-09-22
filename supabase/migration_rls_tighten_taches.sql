-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 7/N : taches_elevage, plan_taches
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase). Aucune self-référence ni dépendance croisée
-- ici (leçon des vagues 5 et 6) : ces policies ne référencent que
-- elevage_cogerants, déjà indépendante.
--
-- ⚠️ Note : plan_taches (ainsi que plan_templates, plans_actifs,
-- plan_template_etapes, non traités dans cette vague) avaient RLS
-- explicitement DÉSACTIVÉE (migration_planning_module.sql) — réactivée ici
-- uniquement pour plan_taches.
--
-- Modèle retenu (identique pour les deux tables) :
--   - SELECT / UPDATE : le propriétaire (uid_eleveur), un cogérant actif,
--     OU l'employé auquel la tâche est assignée (assigne_a / assigned_to —
--     il doit voir et pouvoir cocher ses propres tâches).
--   - INSERT : le propriétaire, un cogérant actif, OU un employé actif de
--     cet élevage (création de tâche depuis Mes Employés).
--   - DELETE : réservé au propriétaire ou à un cogérant actif.
--
-- ⚠️ À TESTER après exécution :
--   1. L'agenda / "Mes Employés → Tâches" affiche normalement les tâches
--      pour l'éleveur, un cogérant actif, ET un employé (ses tâches
--      assignées).
--   2. Créer une tâche, la cocher comme faite, fonctionnent pour ces
--      trois profils.
--   3. Les tâches générées automatiquement par un protocole (plan_taches)
--      s'affichent toujours dans l'agenda.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── taches_elevage ───────────────────────────────────────────────────────
ALTER TABLE taches_elevage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "taches_elevage_related_select" ON taches_elevage;
DROP POLICY IF EXISTS "taches_elevage_related_insert" ON taches_elevage;
DROP POLICY IF EXISTS "taches_elevage_related_update" ON taches_elevage;
DROP POLICY IF EXISTS "taches_elevage_owner_or_cogerant_delete" ON taches_elevage;

CREATE POLICY "taches_elevage_related_select" ON taches_elevage
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR (auth.jwt() ->> 'sub') = assigne_a
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = taches_elevage.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "taches_elevage_related_insert" ON taches_elevage
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = taches_elevage.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR EXISTS (
      SELECT 1 FROM employes e
      WHERE e.uid_eleveur = taches_elevage.uid_eleveur
        AND e.uid_employe = (auth.jwt() ->> 'sub')
        AND e.actif = true
    )
  );

CREATE POLICY "taches_elevage_related_update" ON taches_elevage
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR (auth.jwt() ->> 'sub') = assigne_a
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = taches_elevage.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "taches_elevage_owner_or_cogerant_delete" ON taches_elevage
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = taches_elevage.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- ── plan_taches ──────────────────────────────────────────────────────────
ALTER TABLE plan_taches ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner_taches" ON plan_taches;
DROP POLICY IF EXISTS "employe_taches_read" ON plan_taches;
DROP POLICY IF EXISTS "plan_taches_related_select" ON plan_taches;
DROP POLICY IF EXISTS "plan_taches_related_insert" ON plan_taches;
DROP POLICY IF EXISTS "plan_taches_related_update" ON plan_taches;
DROP POLICY IF EXISTS "plan_taches_owner_or_cogerant_delete" ON plan_taches;

CREATE POLICY "plan_taches_related_select" ON plan_taches
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR (auth.jwt() ->> 'sub') = assigned_to
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = plan_taches.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "plan_taches_related_insert" ON plan_taches
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = plan_taches.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "plan_taches_related_update" ON plan_taches
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR (auth.jwt() ->> 'sub') = assigned_to
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = plan_taches.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "plan_taches_owner_or_cogerant_delete" ON plan_taches
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = plan_taches.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- Vérification
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename IN ('taches_elevage','plan_taches')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "taches_elevage_related_select" ON taches_elevage;
-- DROP POLICY IF EXISTS "taches_elevage_related_insert" ON taches_elevage;
-- DROP POLICY IF EXISTS "taches_elevage_related_update" ON taches_elevage;
-- DROP POLICY IF EXISTS "taches_elevage_owner_or_cogerant_delete" ON taches_elevage;
-- ALTER TABLE taches_elevage DISABLE ROW LEVEL SECURITY;
--
-- DROP POLICY IF EXISTS "plan_taches_related_select" ON plan_taches;
-- DROP POLICY IF EXISTS "plan_taches_related_insert" ON plan_taches;
-- DROP POLICY IF EXISTS "plan_taches_related_update" ON plan_taches;
-- DROP POLICY IF EXISTS "plan_taches_owner_or_cogerant_delete" ON plan_taches;
-- ALTER TABLE plan_taches DISABLE ROW LEVEL SECURITY;
