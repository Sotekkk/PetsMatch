-- ============================================================
-- PetsMatch — Migrations en attente à exécuter sur Supabase
-- ============================================================
-- Où l'exécuter : dashboard Supabase → SQL Editor → New query
-- → coller tout le contenu de ce fichier → Run.
-- Ce script est idempotent (IF NOT EXISTS partout), on peut le relancer
-- sans risque s'il a déjà tourné partiellement.
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 1. Pension — facture réouvrable + lien pour le client
--    `details` (jsonb) : tout ce qu'il faut pour ré-afficher une facture
--       déjà émise (nuits, tarif/nuit, suppléments, TVA, acompte, animal,
--       propriétaire, séjour).
--    `token` (uuid)     : lien public de consultation de la facture,
--       envoyé au propriétaire dans la notification. Route publique
--       /facture-pension/<token>.
--    Sans cette migration : les nouvelles factures s'enregistrent quand
--    même (insert résilient), mais la notification client n'ouvre rien
--    et l'ouverture depuis « Mes factures » n'affiche que le minimum.
-- ────────────────────────────────────────────────────────────

ALTER TABLE pension_factures
  ADD COLUMN IF NOT EXISTS details JSONB,
  ADD COLUMN IF NOT EXISTS token   UUID DEFAULT gen_random_uuid();

CREATE INDEX IF NOT EXISTS idx_pension_factures_token ON pension_factures(token);

-- Rappel : type / acompte_pct ont déjà été ajoutés (migration précédente).
