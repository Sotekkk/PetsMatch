-- PREP01 — Colonnes préparation YouSign sur documents_animaux
-- Idempotent : utilise ADD COLUMN IF NOT EXISTS

-- Statuts étendus (en plus de brouillon / en_attente / signe / archive) :
--   partiellement_signe | annule | expire | refuse

ALTER TABLE documents_animaux
  ADD COLUMN IF NOT EXISTS expires_at          TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancelled_at        TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rejection_reason    TEXT,
  ADD COLUMN IF NOT EXISTS pdf_original_url    TEXT,   -- PDF généré avant signatures (pré-remplissage)
  ADD COLUMN IF NOT EXISTS pdf_signe_url       TEXT,   -- PDF final avec signatures injectées (YouSign ou canvas)
  ADD COLUMN IF NOT EXISTS yousign_id          TEXT;   -- ID de la signature_request YouSign (future intégration)

CREATE INDEX IF NOT EXISTS idx_docs_yousign_id ON documents_animaux(yousign_id)
  WHERE yousign_id IS NOT NULL;

-- Commenter les valeurs de statut autorisées (pas de CHECK pour rester souple pendant la transition)
-- Valeurs gérées par l'application :
--   brouillon | en_attente | partiellement_signe | signe | refuse | annule | expire | archive

COMMENT ON COLUMN documents_animaux.statut IS
  'brouillon | en_attente | partiellement_signe | signe | refuse | annule | expire | archive';
COMMENT ON COLUMN documents_animaux.expires_at IS
  'Date d''expiration du lien de signature (null = pas d''expiration). Mettre statut = expire quand dépassé.';
COMMENT ON COLUMN documents_animaux.pdf_original_url IS
  'URL Supabase Storage du PDF généré avant toute signature (snapshot du HTML au moment de la création).';
COMMENT ON COLUMN documents_animaux.pdf_signe_url IS
  'URL Supabase Storage du PDF final avec signatures injectées. Alimenté par le webhook YouSign ou par l''export canvas.';
COMMENT ON COLUMN documents_animaux.yousign_id IS
  'ID de la signature_request YouSign (format: sr_xxx). Null tant que YouSign n''est pas activé.';
