-- ============================================================
-- PetsMatch — Éducateur : outil de suivi partagé (Phase 4)
-- Devoirs : rappels quotidiens à la famille pour un exercice attribué.
-- `rappels_actifs` (colonne déjà créée en phase 2) = réglage de l'éducateur.
-- `rappels_mutes` = la famille met en pause les rappels de cet exercice.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE exercices_attribues
  ADD COLUMN IF NOT EXISTS rappels_mutes BOOLEAN NOT NULL DEFAULT false;

-- Rappel : la Cloud Function `sendExerciceReminders` (functions/agenda.js,
-- 8h Paris) pousse un rappel quotidien tant que
--   rappels_actifs = true AND rappels_mutes = false
--   AND statut IN ('a_faire','en_cours')
--   AND (echeance IS NULL OR echeance >= aujourd'hui)
-- dédup quotidien via notifs_sent (exo_reminder_<id>_<date>).
-- → `firebase deploy --only functions` après cette migration.
