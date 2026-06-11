-- Champs légaux obligatoires pour la vente d'animaux (Code rural français)
-- Décret n°2013-879 (équidés SIRE), art. L212-10 et L214-8 (chien/chat identification)

ALTER TABLE annonces
  ADD COLUMN IF NOT EXISTS num_identification    TEXT,    -- puce/tatouage animal (chien/chat compagnon)
  ADD COLUMN IF NOT EXISTS num_sire              TEXT,    -- numéro SIRE (équidés, obligatoire)
  ADD COLUMN IF NOT EXISTS num_passeport_equin   TEXT;    -- passeport équin (équidés, optionnel)

COMMENT ON COLUMN annonces.num_identification   IS 'Numéro de puce ICAD ou tatouage — obligatoire chien/chat (art. L212-10 Code rural)';
COMMENT ON COLUMN annonces.num_sire             IS 'Numéro SIRE — obligatoire équidé (Décret n°2013-879)';
COMMENT ON COLUMN annonces.num_passeport_equin  IS 'Numéro de passeport équin (optionnel)';
