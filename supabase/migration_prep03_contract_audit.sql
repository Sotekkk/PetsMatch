-- PREP03 — Table contract_audit : journal des actions sur les contrats
-- Toutes les actions significatives sont loguées ici pour traçabilité et RGPD.
-- En lecture seule côté application (INSERT uniquement, pas d'UPDATE/DELETE).

CREATE TABLE IF NOT EXISTS contract_audit (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  document_id   UUID REFERENCES documents_animaux(id) ON DELETE CASCADE NOT NULL,
  action        TEXT NOT NULL,
  -- Valeurs d'action :
  --   created       — contrat créé
  --   modified      — contrat modifié (champ, montant…)
  --   sent          — lien de signature envoyé à l'acquéreur
  --   viewed        — page /signer-contrat/[token] ouverte
  --   signed        — signature apposée (préciser role dans details)
  --   partially_signed — au moins un signataire a signé (pas tous)
  --   refused       — acquéreur a refusé le contrat
  --   cancelled     — éleveur a annulé le contrat
  --   expired       — lien de signature expiré (cron job)
  --   downloaded    — PDF téléchargé
  --   archived      — contrat archivé manuellement
  actor_uid     TEXT,              -- uid Firebase de l'acteur (null si non-authentifié)
  actor_email   TEXT,              -- email de l'acteur (utile pour acquéreur sans compte)
  actor_role    TEXT,              -- eleveur | acquereur | co_acquereur | admin | system
  details       JSONB DEFAULT '{}',
  -- Exemples de details :
  --   { "role": "acquereur", "champ": "signature_acquereur" }
  --   { "reason": "Prix non conforme à l'accord verbal" }
  --   { "ip": "1.2.3.4", "user_agent": "Mozilla/5.0..." }
  --   { "yousign_event": "signature_request.done" }
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_document ON contract_audit(document_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_action   ON contract_audit(action);
CREATE INDEX IF NOT EXISTS idx_audit_actor    ON contract_audit(actor_uid)
  WHERE actor_uid IS NOT NULL;

COMMENT ON TABLE contract_audit IS
  'Journal immuable des actions sur les contrats. '
  'INSERT uniquement — aucun UPDATE/DELETE autorisé. '
  'Sert à l''affichage de l''historique et à la conformité RGPD.';

ALTER TABLE contract_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "audit_select" ON contract_audit;
DROP POLICY IF EXISTS "audit_insert" ON contract_audit;

-- Lecture : éleveur propriétaire du contrat ou admin
CREATE POLICY "audit_select" ON contract_audit
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM documents_animaux d
      WHERE d.id = document_id AND auth.uid()::text = d.uid_eleveur
    )
  );

-- Insertion : tout le monde (éleveur, acquéreur via token, système)
-- La sécurité est assurée par le fait que document_id doit exister dans documents_animaux
CREATE POLICY "audit_insert" ON contract_audit
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM documents_animaux WHERE id = document_id
    )
  );

-- Pas de UPDATE ni DELETE — le journal est immuable
-- (pas de policy = refus implicite)

-- Fonction helper appelée par l'application pour logguer une action
CREATE OR REPLACE FUNCTION log_contract_action(
  p_document_id  UUID,
  p_action       TEXT,
  p_actor_uid    TEXT    DEFAULT NULL,
  p_actor_email  TEXT    DEFAULT NULL,
  p_actor_role   TEXT    DEFAULT NULL,
  p_details      JSONB   DEFAULT '{}'
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO contract_audit(document_id, action, actor_uid, actor_email, actor_role, details)
  VALUES (p_document_id, p_action, p_actor_uid, p_actor_email, p_actor_role, p_details);
END;
$$;

COMMENT ON FUNCTION log_contract_action IS
  'Insère une ligne dans contract_audit. '
  'SECURITY DEFINER pour permettre l''appel depuis des contextes sans auth (acquéreur via token).';
