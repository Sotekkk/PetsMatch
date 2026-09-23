-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 14/N : carnet de santé
--   vaccinations, visites, traitements, vermifuges, antiparasitaires,
--   allergies, poids, chirurgies, employe_permissions
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- Contrairement aux vagues précédentes, ces 8 tables « carnet de santé »
-- n'ont AUCUNE colonne uid_eleveur/uid_proprietaire à elles : uniquement
-- `animal_id`. L'accès se détermine donc en remontant à l'animal
-- concerné (table `animaux`, sécurisée en vague 5/N) — jamais un EXISTS
-- direct sur `animaux` (qui réappliquerait la policy complexe d'animaux,
-- y compris sa branche « public » via reproducteur_public, ce qui rendrait
-- un carnet de santé lisible publiquement — jamais souhaitable même pour
-- un reproducteur en vitrine). Nouvelle fonction SECURITY DEFINER dédiée :
-- public.can_access_animal_health(animal_id, uid, require_write), qui
-- réplique explicitement propriétaire / cogérant / employé habilité /
-- accès pro (animal_access, via has_animal_access déjà créée en vague 5),
-- SANS jamais inclure la branche publique.
--
-- Un employé n'a le droit d'ÉCRIRE que s'il a la permission granulaire
-- 'write_sante' ou 'write_animaux' (table employe_permissions, jusqu'ici
-- non protégée non plus — ajoutée à cette vague). En LECTURE, tout employé
-- actif de l'élevage suffit (même principe que taches_elevage, vague 7/N).
--
-- Suppression (DELETE) réservée au propriétaire ou à un cogérant actif —
-- ni les employés ni les pros à accès accordé (cohérent avec le principe
-- déjà appliqué aux registres légaux et à `animaux`).
--
-- ⚠️ À TESTER après exécution :
--   1. Le carnet de santé (vaccins, visites, traitements, vermifuges,
--      antiparasitaires, allergies, poids, chirurgies) s'affiche
--      normalement pour l'éleveur, un cogérant actif, ET un employé actif.
--   2. Ajouter une entrée fonctionne pour l'éleveur/cogérant, ET pour un
--      employé avec la permission "Carnet de santé" (write_sante) cochée
--      dans Mes Employés → permissions.
--   3. Un employé SANS cette permission ne peut plus ajouter d'entrée
--      (juste consulter).
--   4. Un vétérinaire/pro santé avec un accès "écriture" accordé
--      (animal_access) peut toujours ajouter une entrée ; un accès
--      "lecture seule" ne peut plus écrire.
--   5. Supprimer une pesée (Suivi de portée) fonctionne toujours pour
--      l'éleveur/cogérant.
--   6. Un profil PUBLIC (reproducteur_public) ne doit PAS exposer son
--      carnet de santé à un visiteur non connecté.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

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
  OR public.has_animal_access(p_animal_id, p_uid, p_require_write);
$$;
GRANT EXECUTE ON FUNCTION public.can_access_animal_health(TEXT, TEXT, BOOLEAN) TO anon, authenticated;

-- ── Tables carnet de santé (schéma identique : id, animal_id, ...) ────────
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['vaccinations','visites','traitements','vermifuges','antiparasitaires','allergies','poids','chirurgies']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;

    EXECUTE format($f$
      CREATE POLICY "%1$s_health_select" ON public.%1$I
        FOR SELECT USING (public.can_access_animal_health(animal_id, (auth.jwt() ->> 'sub'), false))
    $f$, t);

    EXECUTE format($f$
      CREATE POLICY "%1$s_health_insert" ON public.%1$I
        FOR INSERT WITH CHECK (public.can_access_animal_health(animal_id, (auth.jwt() ->> 'sub'), true))
    $f$, t);

    EXECUTE format($f$
      CREATE POLICY "%1$s_health_update" ON public.%1$I
        FOR UPDATE USING (public.can_access_animal_health(animal_id, (auth.jwt() ->> 'sub'), true))
        WITH CHECK (public.can_access_animal_health(animal_id, (auth.jwt() ->> 'sub'), true))
    $f$, t);

    -- Suppression : propriétaire/cogérant uniquement (remonte à animaux,
    -- SANS passer par can_access_animal_health qui autoriserait aussi
    -- employés/pros en écriture).
    EXECUTE format($f$
      CREATE POLICY "%1$s_health_delete" ON public.%1$I
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

-- ── employe_permissions (jusqu'ici non protégée, condition de write ci-dessus) ──
ALTER TABLE employe_permissions ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'employe_permissions'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.employe_permissions', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "employe_permissions_related_select" ON employe_permissions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM employes e
      WHERE e.eleveur_profile_id = employe_permissions.eleveur_profile_id
        AND e.employe_profile_id = employe_permissions.employe_profile_id
        AND (e.uid_eleveur = (auth.jwt() ->> 'sub') OR e.uid_employe = (auth.jwt() ->> 'sub'))
    )
  );

-- INSERT/UPDATE/DELETE : réservés au gérant (lui seul attribue les
-- permissions depuis Mes Employés → permissions) — un cogérant actif
-- passe par le même uid_eleveur sur la ligne `employes` correspondante,
-- donc déjà couvert par la vérification employes ci-dessous.
CREATE POLICY "employe_permissions_eleveur_write" ON employe_permissions
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM employes e
      WHERE e.eleveur_profile_id = employe_permissions.eleveur_profile_id
        AND e.employe_profile_id = employe_permissions.employe_profile_id
        AND (
          e.uid_eleveur = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = e.uid_eleveur
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM employes e
      WHERE e.eleveur_profile_id = employe_permissions.eleveur_profile_id
        AND e.employe_profile_id = employe_permissions.employe_profile_id
        AND (
          e.uid_eleveur = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = e.uid_eleveur
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  );

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('vaccinations','visites','traitements','vermifuges','antiparasitaires','allergies','poids','chirurgies','employe_permissions')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE t TEXT; pol RECORD;
-- BEGIN
--   FOREACH t IN ARRAY ARRAY['vaccinations','visites','traitements','vermifuges','antiparasitaires','allergies','poids','chirurgies','employe_permissions']
--   LOOP
--     FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
--     LOOP
--       EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
--     END LOOP;
--     EXECUTE format('ALTER TABLE %I DISABLE ROW LEVEL SECURITY', t);
--   END LOOP;
-- END $$;
-- DROP FUNCTION IF EXISTS public.can_access_animal_health(TEXT, TEXT, BOOLEAN);
