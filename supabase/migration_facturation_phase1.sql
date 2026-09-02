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
  ADD COLUMN IF NOT EXISTS conditions_escompte      TEXT,   -- défaut appliqué côté app/site
  ADD COLUMN IF NOT EXISTS type_facture             TEXT,   -- NULL/'complete' | 'acompte'
  ADD COLUMN IF NOT EXISTS acompte_pct              NUMERIC; -- % facturé quand type='acompte'

-- Taxi / photographe / toilettage basculent sur ce moteur commun : on distingue
-- leurs factures par `profil_source`.
-- (valeurs possibles : NULL/'eleveur' | 'association' | 'taxi_animalier'
--  | 'photographe' | 'toilettage' | 'garde' | 'education' | 'pension')
