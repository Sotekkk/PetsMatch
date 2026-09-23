-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 16/N : chaleurs, saillies, gestations
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- Même famille que le carnet de santé (vague 14/N) : ces 3 tables n'ont
-- qu'un `animal_id`, l'accès remonte à l'animal (jamais via la branche
-- publique de la policy `animaux` — un suivi repro n'est pas plus public
-- qu'un carnet de santé). MAIS la permission employé concernée est
-- `write_repro`, pas `write_sante` (animal_fiche.dart : `_SuiviReproTab`
-- est gérée par `_tabReadOnly("write_repro")`, distincte du carnet de
-- santé) — nouvelle fonction dédiée public.can_access_animal_repro(),
-- copie de can_access_animal_health() avec cette permission différente.
--
-- Cas particulier `chaleurs` : un employé peut être désigné responsable du
-- suivi des chaleurs d'UN animal précis, indépendamment de la permission
-- write_repro générale (animaux.chaleurs_responsable_uid, cf. Élevage →
-- Employés → 🌸, employes_page.dart). Ce responsable a alors les mêmes
-- droits qu'un employé write_repro sur les chaleurs de CET animal, y
-- compris la suppression (le seul cas où un employé peut supprimer une
-- entrée dans cette famille de tables — cohérent avec l'autonomie voulue
-- de la délégation).
--
-- ⚠️ À TESTER après exécution :
--   1. L'onglet "Suivi Repro" (chaleurs/saillies/gestations) s'affiche
--      normalement pour l'éleveur, un cogérant actif, ET un employé avec
--      la permission "Repro" (write_repro).
--   2. Un employé SANS cette permission ne peut plus rien ajouter/modifier
--      dans cet onglet (lecture seule si accès obtenu autrement, sinon
--      rien du tout).
--   3. Un employé désigné responsable des chaleurs (Élevage → Employés →
--      🌸) sur un animal précis peut toujours ajouter/modifier/supprimer
--      une chaleur pour CET animal, même sans la permission write_repro
--      générale.
--   4. Supprimer une chaleur/saillie/gestation fonctionne pour
--      l'éleveur/cogérant.
--   5. Un profil PUBLIC (reproducteur_public) ne doit PAS exposer son
--      suivi repro à un visiteur non connecté.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- Garde-fou : cette migration référence animaux.chaleurs_responsable_uid
-- (migration_chaleurs_responsable.sql) — au cas où elle n'aurait pas
-- encore été exécutée, idempotent et sans effet si déjà en place.
ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS chaleurs_responsable_uid        TEXT,
  ADD COLUMN IF NOT EXISTS chaleurs_responsable_profile_id UUID;

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
  OR public.has_animal_access(p_animal_id, p_uid, p_require_write);
$$;
GRANT EXECUTE ON FUNCTION public.can_access_animal_repro(TEXT, TEXT, BOOLEAN) TO anon, authenticated;

-- ── saillies, gestations (modèle standard, sans délégation particulière) ──
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['saillies','gestations']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;

    EXECUTE format($f$
      CREATE POLICY "%1$s_repro_select" ON public.%1$I
        FOR SELECT USING (public.can_access_animal_repro(animal_id, (auth.jwt() ->> 'sub'), false))
    $f$, t);

    EXECUTE format($f$
      CREATE POLICY "%1$s_repro_insert" ON public.%1$I
        FOR INSERT WITH CHECK (public.can_access_animal_repro(animal_id, (auth.jwt() ->> 'sub'), true))
    $f$, t);

    EXECUTE format($f$
      CREATE POLICY "%1$s_repro_update" ON public.%1$I
        FOR UPDATE USING (public.can_access_animal_repro(animal_id, (auth.jwt() ->> 'sub'), true))
        WITH CHECK (public.can_access_animal_repro(animal_id, (auth.jwt() ->> 'sub'), true))
    $f$, t);

    EXECUTE format($f$
      CREATE POLICY "%1$s_repro_delete" ON public.%1$I
        FOR DELETE USING (
          EXISTS (
            SELECT 1 FROM animaux a
            WHERE a.id = %1$I.animal_id
              AND (
                a.uid_eleveur = (auth.jwt() ->> 'sub') OR a.uid_proprietaire = (auth.jwt() ->> 'sub')
                OR EXISTS (
                  SELECT 1 FROM elevage_cogerants c
                  WHERE c.uid_gerant = a.uid_eleveur
                    AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
                )
              )
          )
        )
    $f$, t);
  END LOOP;
END $$;

-- ── chaleurs (modèle standard + délégation chaleurs_responsable_uid) ──────
ALTER TABLE chaleurs ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'chaleurs'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.chaleurs', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "chaleurs_repro_select" ON chaleurs
  FOR SELECT USING (
    public.can_access_animal_repro(animal_id, (auth.jwt() ->> 'sub'), false)
    OR EXISTS (SELECT 1 FROM animaux a WHERE a.id = chaleurs.animal_id AND a.chaleurs_responsable_uid = (auth.jwt() ->> 'sub'))
  );

CREATE POLICY "chaleurs_repro_insert" ON chaleurs
  FOR INSERT WITH CHECK (
    public.can_access_animal_repro(animal_id, (auth.jwt() ->> 'sub'), true)
    OR EXISTS (SELECT 1 FROM animaux a WHERE a.id = chaleurs.animal_id AND a.chaleurs_responsable_uid = (auth.jwt() ->> 'sub'))
  );

CREATE POLICY "chaleurs_repro_update" ON chaleurs
  FOR UPDATE USING (
    public.can_access_animal_repro(animal_id, (auth.jwt() ->> 'sub'), true)
    OR EXISTS (SELECT 1 FROM animaux a WHERE a.id = chaleurs.animal_id AND a.chaleurs_responsable_uid = (auth.jwt() ->> 'sub'))
  )
  WITH CHECK (
    public.can_access_animal_repro(animal_id, (auth.jwt() ->> 'sub'), true)
    OR EXISTS (SELECT 1 FROM animaux a WHERE a.id = chaleurs.animal_id AND a.chaleurs_responsable_uid = (auth.jwt() ->> 'sub'))
  );

-- Suppression : propriétaire/cogérant, OU l'employé désigné responsable
-- des chaleurs de CET animal précis (seule exception employé de cette
-- vague — délégation explicite, cf. en-tête).
CREATE POLICY "chaleurs_repro_delete" ON chaleurs
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM animaux a
      WHERE a.id = chaleurs.animal_id
        AND (
          a.uid_eleveur = (auth.jwt() ->> 'sub') OR a.uid_proprietaire = (auth.jwt() ->> 'sub')
          OR a.chaleurs_responsable_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = a.uid_eleveur
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  );

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('chaleurs','saillies','gestations')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('chaleurs','saillies','gestations')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- ALTER TABLE chaleurs DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE saillies DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE gestations DISABLE ROW LEVEL SECURITY;
-- DROP FUNCTION IF EXISTS public.can_access_animal_repro(TEXT, TEXT, BOOLEAN);
