-- ══════════════════════════════════════════════════════════════════════════
-- Employé d'une pension : ouvrir la fiche des pensionnaires (26/11/2026)
-- ══════════════════════════════════════════════════════════════════════════
-- Signalement : l'employé (autorisation « Planning pension ») touchait un
-- pensionnaire et la fiche restait « accès non autorisé », alors que le
-- propriétaire avait bien partagé la fiche avec la pension.
--
-- Cause : l'accès donné par le propriétaire (animal_access, pro_profile_id =
-- la pension) n'était lisible et utilisable que par la pension elle-même et,
-- pour une clinique, par son équipe (droit « vet_patients ») — pas par les
-- employés d'une pension.
--
-- Correctif, scopé au PROFIL pension (employes.eleveur_profile_id =
-- animal_access.pro_profile_id) :
--   1) animal_access : lecture par l'employé « Planning pension » ;
--   2) has_animal_access (fiche, carnet, alimentation via
--      can_access_animal_health…) : l'employé « Planning pension » hérite
--      de l'accès de la pension ; en écriture seulement s'il a aussi
--      « Carnet de santé » (write_sante) ET que le propriétaire a autorisé
--      l'écriture (statut active_write), comme pour la pension.
-- Reprend la définition de migration_clinique_equipe.sql (identique en base
-- au 26/11), branche clinique inchangée.
-- ══════════════════════════════════════════════════════════════════════════

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
        -- Employé de CETTE pension avec « Planning pension » (écriture :
        -- en plus « Carnet de santé »).
        OR EXISTS (
          SELECT 1 FROM employes e
          JOIN employe_permissions ep
            ON ep.eleveur_profile_id = e.eleveur_profile_id
           AND ep.employe_profile_id = e.employe_profile_id
          WHERE e.eleveur_profile_id = aa.pro_profile_id
            AND e.uid_employe = p_uid AND e.actif = true
            AND ep.permission = 'read_planning_pension'
            AND (NOT p_require_write OR EXISTS (
              SELECT 1 FROM employe_permissions ep2
              WHERE ep2.eleveur_profile_id = e.eleveur_profile_id
                AND ep2.employe_profile_id = e.employe_profile_id
                AND ep2.permission = 'write_sante'
            ))
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

-- Accès donnés à la pension, lisibles par son employé « Planning pension ».
DROP POLICY IF EXISTS animal_access_employe_pension_select ON public.animal_access;
CREATE POLICY animal_access_employe_pension_select ON public.animal_access
  FOR SELECT USING (public.pm_employe_profil(pro_profile_id, ARRAY['read_planning_pension']));

NOTIFY pgrst, 'reload schema';

-- ── Vérification ───────────────────────────────────────────────────────────
SELECT policyname, cmd FROM pg_policies WHERE policyname = 'animal_access_employe_pension_select';

-- ── Retour arrière ─────────────────────────────────────────────────────────
-- DROP POLICY IF EXISTS animal_access_employe_pension_select ON public.animal_access;
-- puis réexécuter la définition de has_animal_access de migration_clinique_equipe.sql.
