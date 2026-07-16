-- ============================================================
-- PetsMatch — Colonnes trajet pour le module Taxi animalier
-- (profil_type = 'taxi_animalier'), sur la table `rdv` déjà générique
-- et déjà scopée profil (pro_uid/pro_profile_id/client_uid/client_profile_id
-- — voir migration_rdv_profile_id.sql, aucune colonne de scoping à ajouter).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE rdv
  ADD COLUMN IF NOT EXISTS adresse_depart  TEXT,
  ADD COLUMN IF NOT EXISTS adresse_arrivee TEXT,
  ADD COLUMN IF NOT EXISTS lat_depart      DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS lng_depart      DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS lat_arrivee     DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS lng_arrivee     DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS nombre_animaux  INTEGER DEFAULT 1;
