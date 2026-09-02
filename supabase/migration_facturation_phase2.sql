-- Facturation — Phase 2
-- ============================================================================
-- 1. NUMÉROTATION ATOMIQUE CÔTÉ SERVEUR
--    Une séquence continue, sans rupture, par (émetteur, année, type de profil).
--    Format d'affichage : AAAA-NNNN. Attribuée par trigger BEFORE INSERT sous
--    verrou consultatif → pas de trou, pas de collision en cas de saisie
--    simultanée.
-- ----------------------------------------------------------------------------

ALTER TABLE factures
  ADD COLUMN IF NOT EXISTS numero_seq        INTEGER,
  ADD COLUMN IF NOT EXISTS numero_affichage  TEXT,
  ADD COLUMN IF NOT EXISTS annee_facture     INTEGER;

CREATE OR REPLACE FUNCTION attribuer_numero_facture() RETURNS TRIGGER AS $$
DECLARE
  v_emetteur TEXT;
  v_source   TEXT;
  v_annee    INT;
  v_seq      INT;
BEGIN
  -- Déjà numérotée (réinsertion / import) : on ne touche pas.
  IF NEW.numero_seq IS NOT NULL THEN
    RETURN NEW;
  END IF;

  v_emetteur := COALESCE(NEW.profile_id::text, NEW.uid_eleveur, 'inconnu');
  v_source   := COALESCE(NEW.profil_source, 'eleveur');
  v_annee    := EXTRACT(YEAR FROM COALESCE(NEW.date_facture, CURRENT_DATE))::INT;

  -- Sérialise les inserts concurrents du même périmètre pour la transaction.
  PERFORM pg_advisory_xact_lock(hashtext('facture_num:' || v_emetteur || '|' || v_source || '|' || v_annee));

  SELECT COALESCE(MAX(numero_seq), 0) + 1
    INTO v_seq
    FROM factures
   WHERE annee_facture = v_annee
     AND COALESCE(profil_source, 'eleveur') = v_source
     AND COALESCE(profile_id::text, uid_eleveur, 'inconnu') = v_emetteur;

  NEW.numero_seq        := v_seq;
  NEW.annee_facture     := v_annee;
  NEW.numero_affichage  := v_annee::text || '-' || LPAD(v_seq::text, 4, '0');
  IF NEW.numero_facture IS NULL THEN
    NEW.numero_facture := v_seq;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_attribuer_numero_facture ON factures;
CREATE TRIGGER trg_attribuer_numero_facture
  BEFORE INSERT ON factures
  FOR EACH ROW EXECUTE FUNCTION attribuer_numero_facture();

-- Reprise des factures existantes : on reconstitue la séquence dans l'ordre
-- chronologique de création, par périmètre.
WITH ranked AS (
  SELECT id,
         EXTRACT(YEAR FROM COALESCE(date_facture, created_at::date))::INT AS an,
         ROW_NUMBER() OVER (
           PARTITION BY COALESCE(profile_id::text, uid_eleveur, 'inconnu'),
                        COALESCE(profil_source, 'eleveur'),
                        EXTRACT(YEAR FROM COALESCE(date_facture, created_at::date))
           ORDER BY created_at, numero_facture NULLS LAST, id
         ) AS rn
    FROM factures
   WHERE numero_seq IS NULL
)
UPDATE factures f
   SET numero_seq       = r.rn,
       annee_facture    = r.an,
       numero_affichage = r.an::text || '-' || LPAD(r.rn::text, 4, '0')
  FROM ranked r
 WHERE f.id = r.id;

-- ============================================================================
-- 2. IDENTITÉ DE FACTURATION DU PRO, DANS LE PROFIL
--    (siret, numero_tva, rue_pro, code_postal_pro, ville_pro, pays_pro existent
--     déjà — on complète.)
-- ----------------------------------------------------------------------------

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS forme_juridique_pro TEXT,   -- EI, EURL, SARL, SAS, association…
  ADD COLUMN IF NOT EXISTS capital_social_pro  TEXT,   -- « 5 000 € »
  ADD COLUMN IF NOT EXISTS rcs_pro             TEXT,   -- « RCS Lyon 900 123 456 »
  ADD COLUMN IF NOT EXISTS rm_pro              TEXT,   -- n° répertoire des métiers
  ADD COLUMN IF NOT EXISTS iban_pro            TEXT,
  ADD COLUMN IF NOT EXISTS bic_pro             TEXT,
  ADD COLUMN IF NOT EXISTS regime_tva_pro      TEXT;   -- 'franchise' | 'normal'

-- ============================================================================
-- 3. ARCHIVAGE DU PDF FIGÉ
-- ----------------------------------------------------------------------------

ALTER TABLE factures
  ADD COLUMN IF NOT EXISTS pdf_url   TEXT,
  ADD COLUMN IF NOT EXISTS pdf_hash  TEXT,   -- SHA-256 du PDF émis (preuve d'intégrité)
  ADD COLUMN IF NOT EXISTS pdf_emis_le TIMESTAMPTZ;
