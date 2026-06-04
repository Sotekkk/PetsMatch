-- Ajout colonne email propriétaire dans le registre pension
ALTER TABLE pension_entrees
  ADD COLUMN IF NOT EXISTS proprietaire_email TEXT;
