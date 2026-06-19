-- Table unifiée des documents contractuels liés à l'animal
-- Couvre : contrat_vente, contrat_reservation
-- (certificats_engagement garde sa propre table déjà existante)

CREATE TABLE IF NOT EXISTS documents_animaux (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  animal_id     TEXT REFERENCES animaux(id) ON DELETE CASCADE,
  uid_eleveur   TEXT NOT NULL,
  type          TEXT NOT NULL,  -- contrat_vente | contrat_reservation | certificat_cession
  titre         TEXT,           -- libellé affiché (ex: "Contrat de vente — Rex")
  url           TEXT,           -- Supabase Storage bucket 'contrats'
  statut        TEXT DEFAULT 'brouillon',  -- brouillon | signe | archive
  signe_le      TIMESTAMPTZ,
  metadata      JSONB DEFAULT '{}',
  -- Clés metadata selon type :
  -- contrat_vente/reservation : { acquereur_nom, acquereur_prenom, acquereur_email,
  --                               acquereur_tel, acquereur_adresse, prix, date_cession,
  --                               notes, qualite }
  -- certificat_cession : { acquereur_nom, prix, date_cession }
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_docs_animal   ON documents_animaux(animal_id);
CREATE INDEX IF NOT EXISTS idx_docs_eleveur  ON documents_animaux(uid_eleveur);
CREATE INDEX IF NOT EXISTS idx_docs_type     ON documents_animaux(type);

ALTER TABLE documents_animaux ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "docs_select" ON documents_animaux;
DROP POLICY IF EXISTS "docs_insert" ON documents_animaux;
DROP POLICY IF EXISTS "docs_update" ON documents_animaux;
DROP POLICY IF EXISTS "docs_delete" ON documents_animaux;
CREATE POLICY "docs_select" ON documents_animaux FOR SELECT USING (true);
CREATE POLICY "docs_insert" ON documents_animaux FOR INSERT WITH CHECK (true);
CREATE POLICY "docs_update" ON documents_animaux FOR UPDATE USING (true);
CREATE POLICY "docs_delete" ON documents_animaux FOR DELETE USING (true);
