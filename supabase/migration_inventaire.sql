-- ──────────────────────────────────────────────────────────────────────────────
-- Migration : module inventaire élevage
-- À exécuter dans l'éditeur SQL Supabase
-- ──────────────────────────────────────────────────────────────────────────────

-- Table des articles en stock
CREATE TABLE IF NOT EXISTS inventaire_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid_eleveur     TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  nom             TEXT NOT NULL,
  categorie       TEXT NOT NULL DEFAULT 'autre',
    -- 'alimentation' | 'litiere' | 'medicament' | 'accessoire' | 'hygiene' | 'autre'
  unite           TEXT NOT NULL DEFAULT 'unité',
    -- 'kg' | 'g' | 'L' | 'mL' | 'sac' | 'paquet' | 'boite' | 'unité'
  quantite        NUMERIC NOT NULL DEFAULT 0,
  quantite_alerte NUMERIC,          -- seuil déclenchant la notification
  alerte_active   BOOLEAN NOT NULL DEFAULT true,
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Table des mouvements (consommations + réapprovisionnements)
CREATE TABLE IF NOT EXISTS inventaire_mouvements (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id      UUID NOT NULL REFERENCES inventaire_items(id) ON DELETE CASCADE,
  uid_eleveur  TEXT NOT NULL,
  uid_auteur   TEXT NOT NULL,       -- uid de celui qui a saisi (éleveur ou employé)
  type         TEXT NOT NULL,       -- 'consommation' | 'restock' | 'correction'
  quantite     NUMERIC NOT NULL,    -- toujours positif ; signe déduit du type
  note         TEXT,                -- ex : "paquet de croquettes terminé"
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index pour requêtes fréquentes
CREATE INDEX IF NOT EXISTS idx_inventaire_items_eleveur ON inventaire_items(uid_eleveur);
CREATE INDEX IF NOT EXISTS idx_inventaire_mouvements_item ON inventaire_mouvements(item_id);
CREATE INDEX IF NOT EXISTS idx_inventaire_mouvements_eleveur ON inventaire_mouvements(uid_eleveur);

-- RLS
ALTER TABLE inventaire_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventaire_mouvements ENABLE ROW LEVEL SECURITY;

-- Éleveur : accès total à ses propres articles
CREATE POLICY IF NOT EXISTS "inventaire_items_eleveur"
  ON inventaire_items FOR ALL
  USING (uid_eleveur = auth.uid()::text);

-- Employés actifs : lecture + insert mouvements (via uid_auteur)
CREATE POLICY IF NOT EXISTS "inventaire_items_employe_read"
  ON inventaire_items FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM employes
      WHERE employes.uid_eleveur = inventaire_items.uid_eleveur
        AND employes.uid_employe = auth.uid()::text
        AND employes.actif = true
    )
  );

CREATE POLICY IF NOT EXISTS "inventaire_mouvements_all"
  ON inventaire_mouvements FOR ALL
  USING (
    uid_eleveur = auth.uid()::text
    OR uid_auteur = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM employes
      WHERE employes.uid_eleveur = inventaire_mouvements.uid_eleveur
        AND employes.uid_employe = auth.uid()::text
        AND employes.actif = true
    )
  );
