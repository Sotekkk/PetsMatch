-- Facturation — Phase 2b : numérotation serveur aussi pour la pension
-- ============================================================================
-- La table `pension_factures` est distincte de `factures` : même principe de
-- séquence continue AAAA-NNNN, par (émetteur pension, année).

ALTER TABLE pension_factures
  ADD COLUMN IF NOT EXISTS numero_seq       INTEGER,
  ADD COLUMN IF NOT EXISTS numero_affichage TEXT,
  ADD COLUMN IF NOT EXISTS annee_facture    INTEGER;

CREATE OR REPLACE FUNCTION attribuer_numero_facture_pension() RETURNS TRIGGER AS $$
DECLARE
  v_emetteur TEXT;
  v_annee    INT;
  v_seq      INT;
BEGIN
  IF NEW.numero_seq IS NOT NULL THEN
    RETURN NEW;
  END IF;

  v_emetteur := COALESCE(NEW.pro_profile_id::text, NEW.pro_uid, 'inconnu');
  v_annee    := EXTRACT(YEAR FROM COALESCE(
                  NULLIF((NEW.details ->> 'emiseLe'), '')::timestamptz,
                  now()))::INT;

  PERFORM pg_advisory_xact_lock(hashtext('facture_pension_num:' || v_emetteur || '|' || v_annee));

  SELECT COALESCE(MAX(numero_seq), 0) + 1
    INTO v_seq
    FROM pension_factures
   WHERE annee_facture = v_annee
     AND COALESCE(pro_profile_id::text, pro_uid, 'inconnu') = v_emetteur;

  NEW.numero_seq       := v_seq;
  NEW.annee_facture    := v_annee;
  NEW.numero_affichage := v_annee::text || '-' || LPAD(v_seq::text, 4, '0');
  -- `numero` (TEXT) reste renseigné pour compat : on y met le numéro d'affichage.
  IF NEW.numero IS NULL OR NEW.numero = '' THEN
    NEW.numero := NEW.numero_affichage;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_attribuer_numero_facture_pension ON pension_factures;
CREATE TRIGGER trg_attribuer_numero_facture_pension
  BEFORE INSERT ON pension_factures
  FOR EACH ROW EXECUTE FUNCTION attribuer_numero_facture_pension();

-- Reprise chronologique des factures pension existantes.
WITH ranked AS (
  SELECT id,
         EXTRACT(YEAR FROM COALESCE(date_envoi, created_at))::INT AS an,
         ROW_NUMBER() OVER (
           PARTITION BY COALESCE(pro_profile_id::text, pro_uid, 'inconnu'),
                        EXTRACT(YEAR FROM COALESCE(date_envoi, created_at))
           ORDER BY COALESCE(date_envoi, created_at), id
         ) AS rn
    FROM pension_factures
   WHERE numero_seq IS NULL
)
UPDATE pension_factures f
   SET numero_seq       = r.rn,
       annee_facture    = r.an,
       numero_affichage = r.an::text || '-' || LPAD(r.rn::text, 4, '0')
  FROM ranked r
 WHERE f.id = r.id;
