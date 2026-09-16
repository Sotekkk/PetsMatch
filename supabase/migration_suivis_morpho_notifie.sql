-- ============================================================
-- PetsMatch — Suivi morphologique : envoi de la notif au client décidé
-- par le pro (pas automatique à l'enregistrement).
-- `notifie_a` (TIMESTAMPTZ) trace si/quand la notification "Nouveau bilan
-- disponible" a été envoyée au propriétaire — NULL tant que le pro n'a
-- pas cliqué sur "Envoyer au client".
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE suivis_morpho
  ADD COLUMN IF NOT EXISTS notifie_a TIMESTAMPTZ;
