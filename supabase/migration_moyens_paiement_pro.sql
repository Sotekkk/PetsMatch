-- Moyens de paiement acceptés par un pro (12/11/2026).
--   • user_profiles.moyens_paiement : cases cochées dans le profil pro
--     ('especes', 'cheque', 'cb', 'virement') — public (fiche, prise de RDV).
--   • pm_rib_pro(p_pro_profile_id) : IBAN / BIC du pro (colonnes privées),
--     rendus UNIQUEMENT à un de ses clients (RDV, ou demande de séjour en
--     pension, avec ce profil pro) et seulement si le pro accepte le virement.
-- Site : lib/moyens-paiement.ts ; appli : lib/utils/moyens_paiement.dart.
-- Idempotent. Tester sur le staging d'abord (client du pro / autre compte).

BEGIN;

ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS moyens_paiement TEXT[];

-- Vues publiques régénérées depuis les colonnes (migration_donnees_perso_vues.sql).
SELECT public.pm_recreer_vues_perso();

CREATE OR REPLACE FUNCTION public.pm_rib_pro(p_pro_profile_id UUID)
RETURNS TABLE (iban TEXT, bic TEXT, titulaire TEXT)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NULLIF(trim(p.iban_pro), ''), NULLIF(trim(p.bic_pro), ''),
         COALESCE(NULLIF(trim(p.nom), ''), trim(concat_ws(' ', p.firstname, p.lastname)))
    FROM user_profiles p
   WHERE p.id = p_pro_profile_id
     AND 'virement' = ANY (COALESCE(p.moyens_paiement, '{}'))
     AND NULLIF(trim(p.iban_pro), '') IS NOT NULL
     AND (auth.jwt() ->> 'sub') IS NOT NULL
     AND (
       p.uid = (auth.jwt() ->> 'sub')
       OR EXISTS (SELECT 1 FROM rdv r
                   WHERE r.pro_profile_id = p_pro_profile_id::text
                     AND r.client_uid = (auth.jwt() ->> 'sub'))
       OR EXISTS (SELECT 1 FROM pension_demandes d
                   WHERE d.pro_profile_id = p_pro_profile_id
                     AND d.client_uid = (auth.jwt() ->> 'sub'))
     );
$$;
-- anon aussi : les requêtes passent en rôle anon avec le jeton Firebase.
GRANT EXECUTE ON FUNCTION public.pm_rib_pro(UUID) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- Vérification
SELECT column_name FROM information_schema.columns
 WHERE table_name = 'user_profiles_complet' AND column_name = 'moyens_paiement';

-- ROLLBACK
-- DROP FUNCTION IF EXISTS public.pm_rib_pro(UUID);
-- ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS moyens_paiement;
-- SELECT public.pm_recreer_vues_perso();
