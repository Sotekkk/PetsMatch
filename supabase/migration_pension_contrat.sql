-- ============================================================
-- PetsMatch — Contrat d'hébergement pension (signature électronique)
-- Réutilise documents_animaux (déjà générique, animal_id nullable)
-- pour les contrats de pension, liés à une réservation plutôt
-- qu'à un animal possédé par le pro.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE documents_animaux
  ADD COLUMN IF NOT EXISTS pension_entree_id UUID REFERENCES pension_entrees(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_docs_pension_entree ON documents_animaux(pension_entree_id);

-- type = 'contrat_hebergement' pour ces contrats (colonne déjà libre, pas de CHECK à étendre)
