-- ============================================================
-- PetsMatch — Éducateur/comportementaliste : marquer un créneau
-- comme réservé aux cours individuels, collectifs, ou les deux
-- (NULL = les deux, comportement par défaut inchangé pour tous les
-- autres types de pro).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE creneaux_pro ADD COLUMN IF NOT EXISTS type_prestation TEXT
  CHECK (type_prestation IS NULL OR type_prestation IN ('individuel', 'collectif'));
