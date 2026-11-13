-- Pet-sitter : page unique « Tarifs & forfaits » (13/11/2026).
--   • user_profiles.tarifs_garde_visibles : afficher ou non la grille et les
--     forfaits sur la fiche publique (comme tarifs_sante_visibles). Vrai par
--     défaut : rien ne change pour les pet-sitters qui affichent déjà leurs prix.
--     Les prix restent visibles à la réservation dans tous les cas.
--   • forfaits_garde.affiche_public : forfait proposé sur la fiche et à la
--     réservation ; décoché, il reste utilisable dans les devis.
-- Idempotent.
BEGIN;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS tarifs_garde_visibles BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.forfaits_garde ADD COLUMN IF NOT EXISTS affiche_public BOOLEAN NOT NULL DEFAULT true;
-- Vues publiques régénérées depuis les colonnes (migration_donnees_perso_vues.sql).
SELECT public.pm_recreer_vues_perso();
NOTIFY pgrst, 'reload schema';
COMMIT;

-- ROLLBACK
-- ALTER TABLE public.forfaits_garde DROP COLUMN IF EXISTS affiche_public;
-- ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS tarifs_garde_visibles;
-- SELECT public.pm_recreer_vues_perso();
