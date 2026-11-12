-- Supplément déplacement des rendez-vous à domicile (toiletteur, 12/11/2026).
--   • user_profiles.supplement_domicile : montant TTC réglé par le pro (profil,
--     carte « Trajet à domicile ») — public : affiché à la réservation.
--   • rdv.supplement_deplacement : montant figé à la réservation à domicile,
--     repris en ligne « Déplacement à domicile » sur la facture de la séance.
-- Idempotent.
BEGIN;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS supplement_domicile NUMERIC(10,2);
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS supplement_deplacement NUMERIC(10,2);
-- Vues publiques régénérées depuis les colonnes (migration_donnees_perso_vues.sql).
SELECT public.pm_recreer_vues_perso();
NOTIFY pgrst, 'reload schema';
COMMIT;

-- ROLLBACK
-- ALTER TABLE public.rdv DROP COLUMN IF EXISTS supplement_deplacement;
-- ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS supplement_domicile;
-- SELECT public.pm_recreer_vues_perso();
