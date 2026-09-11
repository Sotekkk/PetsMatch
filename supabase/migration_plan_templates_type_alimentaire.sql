-- ═══════════════════════════════════════════════════════════════════════════
-- Protocoles (plan_templates) — type « Alimentaire » manquant du check
--
-- Le formulaire de création de protocole (fiche animal → Protocoles) propose
-- « Alimentaire » comme type depuis le début, mais la contrainte CHECK posée
-- par migration_planning_module.sql n'autorisait que
-- sanitaire / nettoyage / promenade / socialisation.
-- → Toute création d'un protocole « Alimentaire » échouait avec :
--   PostgrestException 23514 plan_templates_type_chekck
--
-- À exécuter dans Supabase SQL Editor (une seule fois).
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.plan_templates DROP CONSTRAINT IF EXISTS plan_templates_type_chekck;
ALTER TABLE public.plan_templates
  ADD CONSTRAINT plan_templates_type_chekck
  CHECK (type IN ('sanitaire', 'nettoyage', 'promenade', 'socialisation', 'alimentaire'));
