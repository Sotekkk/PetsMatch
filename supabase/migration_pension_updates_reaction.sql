-- ============================================================
-- PetsMatch — Réaction du propriétaire sur une nouvelle de pension
-- (like + réponse texte). Une seule ligne owner_liked/owner_reply par
-- nouvelle car un seul propriétaire réagit par ligne pension_updates.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE pension_updates
  ADD COLUMN IF NOT EXISTS owner_liked BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS owner_reply TEXT,
  ADD COLUMN IF NOT EXISTS owner_reply_at TIMESTAMPTZ;
