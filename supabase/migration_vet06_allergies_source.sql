-- VET06 (complément) : la table allergies avait été oubliée lors de
-- migration_vet06_health_source.sql — un véto pouvait déjà y écrire depuis
-- la fiche animal (vetMode), mais l'entrée n'était pas taguée : pas de
-- badge "Dr. X" côté propriétaire, pas de notification.

ALTER TABLE allergies ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'owner';
ALTER TABLE allergies ADD COLUMN IF NOT EXISTS vet_id TEXT;

UPDATE allergies SET source = 'owner' WHERE source IS NULL;
