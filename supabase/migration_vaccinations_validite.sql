-- Ajoute la date de début de validité d'un vaccin, distincte de la date
-- d'injection (ex : rage = valide légalement 21 jours après l'injection).
-- `date` reste la date d'injection, `date_rappel` reste "valide jusqu'à".
ALTER TABLE vaccinations
  ADD COLUMN IF NOT EXISTS date_validite_debut date;
