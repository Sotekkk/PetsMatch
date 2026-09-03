-- ============================================================
-- PetsMatch — Éducateur : outil de suivi partagé (Phase 5)
-- Bilan structuré : le compte rendu du bilan (1er RDV) devient un livrable
-- avec une recommandation qui pré-remplit un devis.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE education_progression
  ADD COLUMN IF NOT EXISTS type TEXT NOT NULL DEFAULT 'seance'
    CHECK (type IN ('seance', 'bilan')),
  ADD COLUMN IF NOT EXISTS bilan_motif TEXT,
  ADD COLUMN IF NOT EXISTS bilan_observations TEXT,
  ADD COLUMN IF NOT EXISTS bilan_recommandation TEXT,
  ADD COLUMN IF NOT EXISTS bilan_nb_seances_estime INTEGER,
  ADD COLUMN IF NOT EXISTS bilan_forfait_conseille_id UUID;
