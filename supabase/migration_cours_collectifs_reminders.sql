-- ============================================================
-- PetsMatch — Éducateur/comportementaliste : rappels avant séance
-- pour les cours collectifs (les RDV individuels avaient déjà ce
-- mécanisme via rdv.reminder_*_sent, pas les cours collectifs).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE cours_collectifs
  ADD COLUMN IF NOT EXISTS reminder_48h_sent   BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS reminder_24h_sent   BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS reminder_1h_sent    BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS reminder_15min_sent BOOLEAN NOT NULL DEFAULT false;
