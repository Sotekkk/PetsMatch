-- ============================================================
-- PetsMatch — Suivi des chaleurs délégué à un employé
-- ============================================================
-- Où l'exécuter : dashboard Supabase → SQL Editor → New query → Run.
-- Idempotent.
--
-- Quand l'éleveur confie le suivi des chaleurs d'une femelle à un
-- employé, ces colonnes portent le destinataire des rappels « chaleurs »
-- (fonction schedulée sendChaleursNotifications). null = seul le
-- propriétaire est notifié ; renseigné = propriétaire + employé.
-- Retirer l'attribution = remettre à null → l'employé ne reçoit plus rien.
-- ============================================================

ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS chaleurs_responsable_uid        TEXT,
  ADD COLUMN IF NOT EXISTS chaleurs_responsable_profile_id UUID;
