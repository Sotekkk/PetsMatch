-- PREP02 — Table contract_signers : multi-signataires par contrat
-- Permet de gérer éleveur + acquéreur + co-éleveur + témoin (+ futur vétérinaire)
-- et la co-adoption (plusieurs acquéreurs) pour les associations.
-- Utilisée par le canvas SIGN00 dès maintenant, et par YouSign plus tard.

CREATE TABLE IF NOT EXISTS contract_signers (
  id                  UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  document_id         UUID REFERENCES documents_animaux(id) ON DELETE CASCADE NOT NULL,
  role                TEXT NOT NULL,
  -- Valeurs de role : vendeur | acquereur | co_eleveur | temoin | co_acquereur | veterinaire
  nom                 TEXT NOT NULL,
  email               TEXT,
  ordre               INTEGER DEFAULT 1,      -- ordre de sollicitation (1 = premier)
  statut              TEXT DEFAULT 'en_attente',
  -- Valeurs de statut : en_attente | notifie | consulte | signe | refuse
  signe_le            TIMESTAMPTZ,
  signature_b64       TEXT,                   -- canvas base64 (SIGN00) — null si YouSign gère
  yousign_signer_id   TEXT,                   -- ID signataire côté YouSign (future intégration)
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_signers_document   ON contract_signers(document_id);
CREATE INDEX IF NOT EXISTS idx_signers_email      ON contract_signers(email)
  WHERE email IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_signers_yousign    ON contract_signers(yousign_signer_id)
  WHERE yousign_signer_id IS NOT NULL;

COMMENT ON TABLE contract_signers IS
  'Un enregistrement par signataire attendu sur un contrat. '
  'Alimente le statut partiellement_signe sur documents_animaux '
  'quand au moins un signataire a signé mais pas tous.';

COMMENT ON COLUMN contract_signers.role IS
  'vendeur | acquereur | co_eleveur | temoin | co_acquereur | veterinaire';
COMMENT ON COLUMN contract_signers.ordre IS
  'Ordre de sollicitation : 1 = premier. Permet signature séquentielle (vendeur signe avant acquereur).';
COMMENT ON COLUMN contract_signers.signature_b64 IS
  'PNG base64 du canvas (SIGN00). Null quand YouSign est activé (YouSign stocke lui-même la signature).';

ALTER TABLE contract_signers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "signers_select" ON contract_signers;
DROP POLICY IF EXISTS "signers_insert" ON contract_signers;
DROP POLICY IF EXISTS "signers_update" ON contract_signers;
DROP POLICY IF EXISTS "signers_delete" ON contract_signers;

-- Lecture : éleveur propriétaire OU lecture via token du document
CREATE POLICY "signers_select" ON contract_signers
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM documents_animaux d
      WHERE d.id = document_id
        AND (d.token IS NOT NULL OR auth.uid()::text = d.uid_eleveur)
    )
  );

-- Insertion : éleveur propriétaire uniquement
CREATE POLICY "signers_insert" ON contract_signers
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM documents_animaux d
      WHERE d.id = document_id AND auth.uid()::text = d.uid_eleveur
    )
  );

-- Mise à jour : éleveur OU acquéreur via token (pour sauvegarder la signature canvas)
CREATE POLICY "signers_update" ON contract_signers
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM documents_animaux d
      WHERE d.id = document_id
        AND (auth.uid()::text = d.uid_eleveur OR d.token IS NOT NULL)
    )
  );

-- Suppression : éleveur uniquement
CREATE POLICY "signers_delete" ON contract_signers
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM documents_animaux d
      WHERE d.id = document_id AND auth.uid()::text = d.uid_eleveur
    )
  );
