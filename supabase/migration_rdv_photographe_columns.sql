-- ============================================================
-- PetsMatch — Colonne prestation pour le module Photographe animalier
-- (profil_type = 'photographe'), sur la table `rdv` déjà générique.
-- Le lieu du shooting réutilise les colonnes adresse_depart/lat_depart/
-- lng_depart déjà ajoutées pour le taxi (migration_rdv_taxi_columns.sql) —
-- une seule adresse est nécessaire ici (pas de trajet départ/arrivée).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE rdv
  ADD COLUMN IF NOT EXISTS prestation_id UUID REFERENCES prestations_photographe(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_rdv_prestation ON rdv(prestation_id);
