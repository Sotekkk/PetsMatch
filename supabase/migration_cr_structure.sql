-- ════════════════════════════════════════════════════════════════════════
-- Compte rendu vétérinaire structuré : motif, poids du jour, actes réalisés,
-- prescription — pour l'historique du patient en lignes
-- (date · motif · poids · actes · prescription) et l'ordonnance / le CR PDF.
-- (08/10/2026) Le poids saisi alimente aussi la courbe de poids (table poids).
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════

ALTER TABLE public.comptes_rendus
  ADD COLUMN IF NOT EXISTS motif        text,
  ADD COLUMN IF NOT EXISTS poids        numeric,
  ADD COLUMN IF NOT EXISTS actes        text[],
  ADD COLUMN IF NOT EXISTS prescription text;
