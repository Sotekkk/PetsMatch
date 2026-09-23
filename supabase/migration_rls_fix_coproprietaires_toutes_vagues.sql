-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — correctif transversal : co-propriétaires oubliés dans
-- plusieurs vagues (14, 16, 17, 18)
-- ══════════════════════════════════════════════════════════════════════════
-- Suite à la remarque sur la vague 19/N (éducation) : le même oubli existe
-- dans TOUTES les fonctions/policies qui résolvent « propriétaire de
-- l'animal » depuis ces vagues — elles vérifient uid_eleveur/uid_proprietaire
-- + cogérant, mais jamais animaux_proprietes (un co-propriétaire actuel de
-- l'animal, fonctionnalité « Co-propriétaires d'un animal »). Revue
-- systématique de toutes les vagues RLS pour ce trou précis :
--
--   - vague 14 (carnet de santé)  : public.can_access_animal_health   → à corriger
--   - vague 16 (repro)            : public.can_access_animal_repro    → à corriger
--   - vague 17 (ostéo/morpho)     : public.is_animal_owner_or_cogerant → à corriger
--     (corrige du même coup can_access_animal_morpho et
--     can_access_suivi_morpho, qui l'appellent)
--   - vague 18 (pension_updates)  : policy inline, jamais de fonction
--     partagée → à corriger directement
--   - vague 19 (éducation)        : déjà corrigé séparément
--     (is_animal_owner_or_related)
--
-- Vagues déjà vérifiées et NON concernées par ce trou (pas de résolution
-- « propriétaire de l'animal » du tout, ou modèle différent à dessein) :
-- user_profiles, notifications, messagerie, employes/elevage_cogerants,
-- animaux/animaux_proprietes (référence, déjà correct), animal_access/
-- likes/favoris, taches_elevage/plan_taches (élevage-scopé, pas
-- animal-scopé), agenda_events, abonnements, annonces, registres (registre
-- légal élevage, volontairement pas re-scopé par propriétaire courant),
-- rdv (deux parties humaines, pas un concept de propriété animale), users,
-- contrats/factures (documents élevage), pension_entrees/cles_clients/
-- tarifs_clients_garde/garde_entraide (aucune n'a de concept « propriétaire
-- courant de l'animal »).
--
-- ⚠️ À TESTER après exécution :
--   1. Un co-propriétaire d'un animal (ajouté via "Co-propriétaires") voit
--      désormais bien le carnet de santé, le suivi repro (chaleurs/
--      saillies/gestations) et le suivi ostéo/morpho de cet animal — ce
--      qui n'était pas le cas avant ce correctif.
--   2. Le propriétaire principal continue de voir tout normalement (rien
--      ne doit changer pour lui).
--   3. Les photos/vidéos de pension liées à un animal (pension_updates)
--      sont désormais visibles aussi par un co-propriétaire.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── vague 17 : is_animal_owner_or_cogerant (corrige aussi can_access_animal_morpho / can_access_suivi_morpho) ──
CREATE OR REPLACE FUNCTION public.is_animal_owner_or_cogerant(p_animal_id TEXT, p_uid TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM animaux a
    WHERE a.id = p_animal_id
      AND (
        a.uid_eleveur = p_uid OR a.uid_proprietaire = p_uid
        OR EXISTS (
          SELECT 1 FROM elevage_cogerants c
          WHERE c.uid_gerant = a.uid_eleveur
            AND c.uid_cogerant = p_uid AND c.statut = 'actif' AND c.date_fin IS NULL
        )
      )
  )
  OR EXISTS (
    SELECT 1 FROM animaux_proprietes p
    WHERE p.animal_id = p_animal_id
      AND p.uid_proprio = p_uid
      AND p.date_fin IS NULL
  );
$$;

-- ── vague 14 : can_access_animal_health ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.can_access_animal_health(p_animal_id TEXT, p_uid TEXT, p_require_write BOOLEAN DEFAULT false)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM animaux a
    WHERE a.id = p_animal_id
      AND (
        a.uid_eleveur = p_uid OR a.uid_proprietaire = p_uid
        OR EXISTS (
          SELECT 1 FROM elevage_cogerants c
          WHERE c.uid_gerant = a.uid_eleveur
            AND c.uid_cogerant = p_uid AND c.statut = 'actif' AND c.date_fin IS NULL
        )
        OR EXISTS (
          SELECT 1 FROM employes e
          WHERE e.uid_eleveur = a.uid_eleveur
            AND e.uid_employe = p_uid
            AND e.actif = true
            AND (
              NOT p_require_write
              OR EXISTS (
                SELECT 1 FROM employe_permissions ep
                WHERE ep.eleveur_profile_id = e.eleveur_profile_id
                  AND ep.employe_profile_id = e.employe_profile_id
                  AND ep.permission IN ('write_sante', 'write_animaux')
              )
            )
        )
      )
  )
  OR EXISTS (
    SELECT 1 FROM animaux_proprietes p
    WHERE p.animal_id = p_animal_id
      AND p.uid_proprio = p_uid
      AND p.date_fin IS NULL
  )
  OR public.has_animal_access(p_animal_id, p_uid, p_require_write);
$$;

-- ── vague 16 : can_access_animal_repro ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.can_access_animal_repro(p_animal_id TEXT, p_uid TEXT, p_require_write BOOLEAN DEFAULT false)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM animaux a
    WHERE a.id = p_animal_id
      AND (
        a.uid_eleveur = p_uid OR a.uid_proprietaire = p_uid
        OR EXISTS (
          SELECT 1 FROM elevage_cogerants c
          WHERE c.uid_gerant = a.uid_eleveur
            AND c.uid_cogerant = p_uid AND c.statut = 'actif' AND c.date_fin IS NULL
        )
        OR EXISTS (
          SELECT 1 FROM employes e
          WHERE e.uid_eleveur = a.uid_eleveur
            AND e.uid_employe = p_uid
            AND e.actif = true
            AND (
              NOT p_require_write
              OR EXISTS (
                SELECT 1 FROM employe_permissions ep
                WHERE ep.eleveur_profile_id = e.eleveur_profile_id
                  AND ep.employe_profile_id = e.employe_profile_id
                  AND ep.permission IN ('write_repro', 'write_animaux')
              )
            )
        )
      )
  )
  OR EXISTS (
    SELECT 1 FROM animaux_proprietes p
    WHERE p.animal_id = p_animal_id
      AND p.uid_proprio = p_uid
      AND p.date_fin IS NULL
  )
  OR public.has_animal_access(p_animal_id, p_uid, p_require_write);
$$;

-- ── vague 18 : pension_updates (policies inline, pas de fonction partagée) ─
DROP POLICY IF EXISTS "pension_updates_select" ON pension_updates;
DROP POLICY IF EXISTS "pension_updates_insert" ON pension_updates;
DROP POLICY IF EXISTS "pension_updates_update" ON pension_updates;
DROP POLICY IF EXISTS "pension_updates_delete" ON pension_updates;

CREATE POLICY "pension_updates_select" ON pension_updates
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = pension_updates.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR (animal_id IS NOT NULL AND public.is_animal_owner_or_cogerant(animal_id, (auth.jwt() ->> 'sub')))
  );

CREATE POLICY "pension_updates_insert" ON pension_updates
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = pension_updates.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "pension_updates_update" ON pension_updates
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = pension_updates.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = pension_updates.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "pension_updates_delete" ON pension_updates
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = pension_updates.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- Vérification : cette requête doit renvoyer les 3 fonctions corrigées.
SELECT proname, pg_get_functiondef(oid) LIKE '%animaux_proprietes%' AS verifie_co_proprietaires
FROM pg_proc
WHERE proname IN ('is_animal_owner_or_cogerant', 'can_access_animal_health', 'can_access_animal_repro');

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue : relancer les migrations
-- d'origine des vagues 14 (migration_rls_tighten_carnet_sante.sql), 16
-- (migration_rls_tighten_repro.sql), 17
-- (migration_rls_tighten_osteo_morpho.sql) et 18
-- (migration_rls_tighten_pension_garde.sql), qui recréent les fonctions/
-- policies sans le co-propriétaire.
-- ══════════════════════════════════════════════════════════════════════════
