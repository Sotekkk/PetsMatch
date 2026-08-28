-- ============================================================
-- PetsMatch — Migrations en attente à exécuter sur Supabase
-- ============================================================
-- Où l'exécuter : dashboard Supabase → SQL Editor → New query
-- → coller tout le contenu de ce fichier → Run.
-- Ce script est idempotent (IF NOT EXISTS partout), on peut le relancer
-- sans risque s'il a déjà tourné partiellement.
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 1. Pension — détail de facture réouvrable
--    `details` (jsonb) stocke tout ce qu'il faut pour ré-afficher une
--    facture déjà émise depuis « Mes factures » sur le site (nuits,
--    tarif/nuit, suppléments, TVA, acompte, animal, propriétaire, séjour).
--    Sans cette migration, l'ouverture d'une facture depuis la liste
--    n'affiche que les infos minimales de la ligne.
-- ────────────────────────────────────────────────────────────

ALTER TABLE pension_factures
  ADD COLUMN IF NOT EXISTS details JSONB;

-- Rappel : type / acompte_pct ont déjà été ajoutés (migration précédente).
