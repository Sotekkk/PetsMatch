-- ============================================================
-- PetsMatch — Pension : tarification automatisée (Phase 2, item 1/4)
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

-- Config tarifaire du pro pension : tranches de poids (prix seul/partagé)
-- + réductions séjour long. Structure JSON :
-- {
--   "tranches_poids": [
--     {"poids_max": 5,  "prix_seul": 15, "prix_partage": 10},
--     {"poids_max": 15, "prix_seul": 20, "prix_partage": 14},
--     {"poids_max": null, "prix_seul": 30, "prix_partage": 22}
--   ],
--   "reductions_long_sejour": [
--     {"min_nuits": 7,  "pourcentage": 10},
--     {"min_nuits": 14, "pourcentage": 15}
--   ]
-- }
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS tarifs_pension JSONB;
