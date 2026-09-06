-- Certificat d'engagement : signature manuscrite + PDF figé archivé.
-- Aligne le certificat sur les contrats (documents_animaux) : signature au
-- doigt côté acquéreur, PDF horodaté + hash conservé comme preuve.
ALTER TABLE certificats_engagement
  ADD COLUMN IF NOT EXISTS signature_acquereur TEXT,   -- data-URL PNG du tracé
  ADD COLUMN IF NOT EXISTS signataire_nom      TEXT,   -- nom saisi au moment de signer
  ADD COLUMN IF NOT EXISTS signe_le            TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS pdf_hash            TEXT;
-- pdf_url existe déjà. statut garde son CHECK ('envoye','lu','signe','refuse').
