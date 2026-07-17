-- ============================================================
-- PetsMatch — Taxi animalier : tarifs de course
-- Contrairement à photographe/toilettage (catalogue de prestations),
-- le taxi n'a qu'un seul type de course : prise en charge + prix au km
-- (calculé à la réservation depuis lat/lng départ-arrivée déjà stockés
-- sur `rdv`, cf. migration_rdv_taxi_columns.sql), avec un minimum.
-- Simple JSONB sur le profil, pas de nouvelle table.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS tarifs_taxi JSONB DEFAULT '{}'::jsonb;
  -- {"prise_en_charge": 5, "prix_km": 1.5, "minimum": 15}
