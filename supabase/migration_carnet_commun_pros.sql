-- ══════════════════════════════════════════════════════════════════════════
-- Carnet commun entre professionnels de santé (décision du 30/10/2026)
-- ══════════════════════════════════════════════════════════════════════════
-- Fiche créée par un autre pro (animal_access.statut = 'identite',
-- migration_puce_unique.sql) : un vétérinaire ou un ostéo / kiné (profil
-- 'sante') rattaché lit ET écrit le carnet commun — vaccinations,
-- vermifuges, antiparasitaires, poids, allergies, traitements.
-- Restent privés à chaque pro (policies RESTRICTIVE *_confidentiel_pro) :
-- comptes rendus, ordonnances, radios, consultations, chirurgies, visites,
-- séances. Suppression : inchangée (propriétaire de la fiche seulement).
-- Toiletteur, pension, éducateur… : identité seule, inchangé.
-- Accès : titulaire du profil, son équipe (cogérant, employé) ou employé
-- avec le droit « patients ».
-- Idempotent. Staging d'abord.
-- ══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.pm_carnet_commun(p_animal text, p_uid text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_uid IS NOT NULL AND EXISTS (
    SELECT 1 FROM animal_access aa
    JOIN user_profiles up ON up.id = aa.pro_profile_id
    WHERE aa.animal_id = p_animal AND aa.statut = 'identite'
      AND up.profile_type IN ('veterinaire', 'sante')
      AND (public.pm_meme_equipe(up.uid, p_uid)
           OR EXISTS (
             SELECT 1 FROM employes e
             JOIN employe_permissions ep
               ON ep.eleveur_profile_id = e.eleveur_profile_id
              AND ep.employe_profile_id = e.employe_profile_id
             WHERE e.eleveur_profile_id = aa.pro_profile_id
               AND e.uid_employe = p_uid AND e.actif = true
               AND ep.permission = 'vet_patients'))
  );
$$;
GRANT EXECUTE ON FUNCTION public.pm_carnet_commun(text, text) TO anon, authenticated;

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['vaccinations', 'vermifuges', 'antiparasitaires', 'poids', 'allergies', 'traitements'] LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_carnet_commun_select', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_carnet_commun_insert', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_carnet_commun_update', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO anon, authenticated '
                   'USING (public.pm_carnet_commun(animal_id, auth.jwt() ->> ''sub''))', t || '_carnet_commun_select', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR INSERT TO anon, authenticated '
                   'WITH CHECK (public.pm_carnet_commun(animal_id, auth.jwt() ->> ''sub''))', t || '_carnet_commun_insert', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR UPDATE TO anon, authenticated '
                   'USING (public.pm_carnet_commun(animal_id, auth.jwt() ->> ''sub'')) '
                   'WITH CHECK (public.pm_carnet_commun(animal_id, auth.jwt() ->> ''sub''))', t || '_carnet_commun_update', t);
  END LOOP;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ROLLBACK :
-- DROP POLICY IF EXISTS <table>_carnet_commun_select / _insert / _update ON public.<table>
--   (vaccinations, vermifuges, antiparasitaires, poids, allergies, traitements) ;
-- DROP FUNCTION IF EXISTS public.pm_carnet_commun(text, text);
