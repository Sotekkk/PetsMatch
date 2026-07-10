-- ============================================================
-- PetsMatch — Contrat de prestation garde (petsitter/promeneur), signature électronique
-- Réutilise documents_animaux (déjà générique, animal_id nullable)
-- pour les contrats garde, liés à un RDV/visite plutôt qu'à un
-- séjour (pas de concept d'entrée/sortie côté garde).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE documents_animaux
  ADD COLUMN IF NOT EXISTS rdv_id UUID REFERENCES rdv(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_docs_rdv ON documents_animaux(rdv_id);

-- type = 'contrat_garde' pour ces contrats (colonne déjà libre, pas de CHECK à étendre)
