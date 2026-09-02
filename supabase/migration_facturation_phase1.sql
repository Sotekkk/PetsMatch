-- Facturation — Phase 1 : gabarit unique conforme
-- ----------------------------------------------------------------------------
-- Champs d'identité légale de l'émetteur et du client, portés PAR facture
-- (photo au moment de l'émission — ne bouge plus même si le profil change).
-- Utilisé par éleveur / association / garde / éducateur (table `factures`).

ALTER TABLE factures
  ADD COLUMN IF NOT EXISTS tel_emetteur             TEXT,
  ADD COLUMN IF NOT EXISTS forme_juridique_emetteur TEXT,   -- EI, EURL, SARL, SAS, association…
  ADD COLUMN IF NOT EXISTS capital_emetteur         TEXT,   -- ex. « 5 000 € » (sociétés)
  ADD COLUMN IF NOT EXISTS rcs_emetteur             TEXT,   -- « RCS Lyon 900 123 456 » (commerçant)
  ADD COLUMN IF NOT EXISTS rm_emetteur              TEXT,   -- n° au répertoire des métiers (artisan)
  ADD COLUMN IF NOT EXISTS siret_client             TEXT,
  ADD COLUMN IF NOT EXISTS tva_client               TEXT,
  ADD COLUMN IF NOT EXISTS conditions_escompte      TEXT;   -- défaut appliqué côté app/site
