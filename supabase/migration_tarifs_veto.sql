-- ============================================================
-- PetsMatch — Tarifs vétérinaire + déplacement à domicile
-- Mirror de migration_tarifs_sante.sql : grille de tarifs affichable sur la
-- vitrine publique du vétérinaire (opt-in via tarifs_veto_visibles).
--   tarifs_veto         : prestations canoniques, ex. {"consultation": 45,
--                         "sterilisation_chienne_25": 320} (stérilisations
--                         chien par tranche de poids) — cf. pro_profile_edit.dart
--                         _prestationsVeto / website lib/tarifs-veto.ts
--   tarifs_veto_visibles: opt-in — tant que false, la vitrine est inchangée.
--   tarifs_veto_extra   : prestations libres [{"label","prix","description"}].
--   se_deplace          : le pro fait des visites à domicile. false = au
--                         cabinet uniquement (le rayon ne s'affiche plus et
--                         ne limite plus la recherche « proche de moi »).
-- Exécuter dans Supabase SQL Editor (idempotent).
-- ============================================================

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS tarifs_veto          JSONB   DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS tarifs_veto_visibles BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS tarifs_veto_extra    JSONB   DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS se_deplace           BOOLEAN DEFAULT true;

-- Nouvelles colonnes publiques : vue masquée + droits de lecture par colonne
-- (sinon illisibles pour anon/authenticated depuis la phase 2 données perso).
SELECT public.pm_recreer_vues_perso();
SELECT public.pm_appliquer_droits_perso();
