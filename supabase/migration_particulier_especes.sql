-- ════════════════════════════════════════════════════════════════════════
-- Profil particulier : espèces cochées enregistrées comme un vrai choix
-- (avant : seulement fondues dans le texte libre projet_adoption, donc
-- introuvables ensuite dans Mon profil).
--   • especes_possedees : « Quelles espèces avez-vous ? » (inscription, si la
--     personne a déjà un animal) ;
--   • especes_projet    : espèces du projet d'adoption.
-- Codes : chien, chat, lapin, cheval, oiseau, nac, reptile, autre (même liste
-- appli / site). Modifiables dans Mon profil (appli + site).
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS especes_possedees text[];
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS especes_projet text[];

-- Vues masquées + droits de lecture par colonne (colonnes publiques).
SELECT public.pm_recreer_vues_perso();
SELECT public.pm_appliquer_droits_perso();

COMMIT;
