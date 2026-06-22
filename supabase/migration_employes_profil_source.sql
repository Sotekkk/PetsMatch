-- Séparation des employés par profil pour les comptes mixtes (éleveur + association)
ALTER TABLE employes
  ADD COLUMN IF NOT EXISTS profil_source TEXT DEFAULT 'eleveur';

CREATE INDEX IF NOT EXISTS idx_employes_profil_source ON employes(profil_source);
