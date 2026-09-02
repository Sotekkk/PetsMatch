-- Facturation — Phase 3 : inaltérabilité (loi anti-fraude TVA, art. 286-I-3° bis CGI)
-- ============================================================================

-- 1. Facture d'avoir : rattachement à la facture corrigée.
ALTER TABLE factures
  ADD COLUMN IF NOT EXISTS facture_parente_id TEXT;

-- 2. Journal d'audit — append only (jamais d'UPDATE ni de DELETE).
CREATE TABLE IF NOT EXISTS factures_journal (
  id          BIGSERIAL PRIMARY KEY,
  facture_id  TEXT NOT NULL,
  action      TEXT NOT NULL,          -- 'creation' | 'statut' | 'avoir'
  detail      JSONB,
  acteur_uid  TEXT,
  hash        TEXT,                   -- empreinte du PDF émis, si connue
  cree_le     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_factures_journal_facture ON factures_journal (facture_id);

ALTER TABLE factures_journal ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS factures_journal_insert ON factures_journal;
DROP POLICY IF EXISTS factures_journal_select ON factures_journal;
CREATE POLICY factures_journal_insert ON factures_journal FOR INSERT WITH CHECK (true);
CREATE POLICY factures_journal_select ON factures_journal FOR SELECT USING (true);
-- Pas de policy UPDATE / DELETE → interdits pour tout le monde (RLS activé).
REVOKE UPDATE, DELETE ON factures_journal FROM anon, authenticated;

-- 3. Garde-fou : une facture émise est inaltérable ; toute correction passe par
--    un avoir. Journalise création et changements de statut.
CREATE OR REPLACE FUNCTION factures_garde_fou() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO factures_journal (facture_id, action, detail, acteur_uid, hash)
    VALUES (NEW.id, COALESCE(NULLIF(NEW.type_facture, ''), 'creation'),
            jsonb_build_object(
              'numero',   NEW.numero_affichage,
              'total_ttc', NEW.total_ttc,
              'client',   NEW.nom_client,
              'parente',  NEW.facture_parente_id),
            NEW.uid_eleveur, NEW.pdf_hash);
    RETURN NEW;

  ELSIF TG_OP = 'UPDATE' THEN
    -- Seul un brouillon peut voir son contenu modifié.
    IF COALESCE(OLD.statut, 'emise') <> 'brouillon'
       AND ROW(NEW.lignes, NEW.total_ht, NEW.total_tva, NEW.total_ttc,
               NEW.nom_client, NEW.prenom_client, NEW.rue_client, NEW.cp_client,
               NEW.ville_client, NEW.date_facture, NEW.date_prestation,
               NEW.nom_emetteur, NEW.siret_emetteur, NEW.numero_seq,
               NEW.numero_affichage, NEW.regime_tva)
       IS DISTINCT FROM
           ROW(OLD.lignes, OLD.total_ht, OLD.total_tva, OLD.total_ttc,
               OLD.nom_client, OLD.prenom_client, OLD.rue_client, OLD.cp_client,
               OLD.ville_client, OLD.date_facture, OLD.date_prestation,
               OLD.nom_emetteur, OLD.siret_emetteur, OLD.numero_seq,
               OLD.numero_affichage, OLD.regime_tva)
    THEN
      RAISE EXCEPTION 'Facture émise inaltérable — émettez une facture d''avoir pour corriger.';
    END IF;

    IF NEW.statut IS DISTINCT FROM OLD.statut THEN
      INSERT INTO factures_journal (facture_id, action, detail, acteur_uid)
      VALUES (NEW.id, 'statut',
              jsonb_build_object('de', OLD.statut, 'vers', NEW.statut),
              NEW.uid_eleveur);
    END IF;
    RETURN NEW;

  ELSIF TG_OP = 'DELETE' THEN
    IF COALESCE(OLD.statut, 'emise') <> 'brouillon' THEN
      RAISE EXCEPTION 'Une facture émise ne peut pas être supprimée (annulez-la ou émettez un avoir).';
    END IF;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_factures_garde_fou ON factures;
CREATE TRIGGER trg_factures_garde_fou
  BEFORE INSERT OR UPDATE OR DELETE ON factures
  FOR EACH ROW EXECUTE FUNCTION factures_garde_fou();

-- Note : l'archivage du PDF (pdf_url / pdf_hash / pdf_emis_le) et le passage
-- payee/annulee restent autorisés — ces colonnes ne sont pas dans le verrou.
