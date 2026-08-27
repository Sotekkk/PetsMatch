-- ============================================================
-- PetsMatch — Migrations en attente à exécuter sur Supabase
-- ============================================================
-- Où l'exécuter : dashboard Supabase → SQL Editor → New query
-- → coller tout le contenu de ce fichier → Run.
-- Ce script est idempotent (IF NOT EXISTS partout), on peut le relancer
-- sans risque s'il a déjà tourné partiellement.
--
-- Migrations précédentes (reservations_animaux, taches_elevage mirror…)
-- déjà appliquées — ce fichier ne contient plus que la suivante.
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 1. Pension — factures d'acompte / solde
--    Ajoute un type à pension_factures :
--      'complete' : facture du séjour complet (défaut, comportement actuel)
--      'acompte'  : acompte demandé à la réservation / l'entrée
--      'solde'    : facture du solde après un acompte
--    acompte_pct : pourcentage retenu quand type = 'acompte' (ex. 30)
--    Sans cette migration, l'option "Facture d'acompte" du modal de
--    facturation pension échoue (colonne inconnue).
-- ────────────────────────────────────────────────────────────

ALTER TABLE pension_factures
  ADD COLUMN IF NOT EXISTS type        TEXT NOT NULL DEFAULT 'complete',
  ADD COLUMN IF NOT EXISTS acompte_pct NUMERIC;

CREATE INDEX IF NOT EXISTS idx_pension_factures_type ON pension_factures(type);
