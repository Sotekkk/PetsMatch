-- ══════════════════════════════════════════════════════════════════════════
-- Pension : son propre modèle de contrat d'hébergement (07/11/2026)
-- ══════════════════════════════════════════════════════════════════════════
-- user_profiles.pension_contrat_modele = { "url": "...", "nom": "Mon contrat.pdf", "le": "2026-11-07T…" }
-- Chargé une fois dans Tarifs (PDF ou photo convertie en PDF, stockage
-- `documents`, documents-pro/<uid>/…). À la finalisation de l'arrivée, la
-- pension choisit ce contrat au lieu du contrat PetsMatch : une ligne
-- documents_animaux type `contrat_document_pro` rattachée au séjour
-- (pension_entree_id), signée en ligne comme les contrats chargés des autres
-- pros. NULL = pas de modèle. Rien ne change pour l'existant.
-- ══════════════════════════════════════════════════════════════════════════

BEGIN;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS pension_contrat_modele JSONB;
COMMIT;

SELECT pm_recreer_vues_perso();
