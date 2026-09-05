-- Délai minimum de réservation d'un RDV (choix du pro).
-- NULL / 0 = aucun délai (comportement historique : « aujourd'hui + 30 min »).
-- Valeurs proposées dans l'UI : 0 / 12 / 24 / 48 / 72 heures.

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS delai_min_reservation_h SMALLINT;

COMMENT ON COLUMN user_profiles.delai_min_reservation_h IS
  'Délai minimum (heures) entre maintenant et un RDV réservable. NULL/0 = aucun.';
