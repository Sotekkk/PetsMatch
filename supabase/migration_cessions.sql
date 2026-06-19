-- Table cessions : workflow de transfert en 2 étapes avec signatures
CREATE TABLE IF NOT EXISTS cessions (
  id               UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  animal_id        TEXT REFERENCES animaux(id) ON DELETE CASCADE,
  uid_eleveur      TEXT NOT NULL,
  uid_acquereur    TEXT,                        -- null si non-utilisateur PetsMatch
  email_acquereur  TEXT,
  nom_acquereur    TEXT,
  tel_acquereur    TEXT,
  adresse_acquereur TEXT,
  qualite          TEXT DEFAULT 'particulier',
  prix             NUMERIC,
  notes            TEXT,
  date_cession     DATE,
  -- Statuts : en_attente_acquereur → signe_acquereur → confirme (= sorti) | revoquee
  statut           TEXT DEFAULT 'en_attente_acquereur',
  token            TEXT UNIQUE DEFAULT gen_random_uuid()::TEXT,
  signature_acquereur TEXT,                     -- base64 PNG
  signature_eleveur   TEXT,                     -- base64 PNG
  contrat_url      TEXT,
  certificat_url   TEXT,
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  signed_acquereur_at TIMESTAMPTZ,
  confirmed_at        TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_cessions_animal    ON cessions(animal_id);
CREATE INDEX IF NOT EXISTS idx_cessions_token     ON cessions(token);
CREATE INDEX IF NOT EXISTS idx_cessions_acquereur ON cessions(uid_acquereur);
CREATE INDEX IF NOT EXISTS idx_cessions_eleveur   ON cessions(uid_eleveur);

ALTER TABLE cessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "cessions_select" ON cessions;
DROP POLICY IF EXISTS "cessions_insert" ON cessions;
DROP POLICY IF EXISTS "cessions_update" ON cessions;
CREATE POLICY "cessions_select" ON cessions FOR SELECT USING (true);
CREATE POLICY "cessions_insert" ON cessions FOR INSERT WITH CHECK (true);
CREATE POLICY "cessions_update" ON cessions FOR UPDATE USING (true);

-- Le statut 'cession_en_cours' est ajouté au champ statut des animaux
-- (pas de contrainte CHECK pour garder la flexibilité)
-- Valeurs possibles : present | cession_en_cours | sorti | decede (éleveur)
--                    en_soin | disponible | en_fa | adopte | transfere (asso)
