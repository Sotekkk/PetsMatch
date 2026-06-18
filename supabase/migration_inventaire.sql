-- ──────────────────────────────────────────────────────────────────────────────
-- Migration : module inventaire élevage
-- ÉTAPE 1 — Tables + index (à exécuter en premier)
-- ──────────────────────────────────────────────────────────────────────────────

-- Table des articles en stock
CREATE TABLE IF NOT EXISTS inventaire_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid_eleveur     TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  nom             TEXT NOT NULL,
  categorie       TEXT NOT NULL DEFAULT 'autre',
  unite           TEXT NOT NULL DEFAULT 'unité',
  quantite        NUMERIC NOT NULL DEFAULT 0,
  quantite_alerte NUMERIC,
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
  uid_auteur   TEXT NOT NULL,
  type         TEXT NOT NULL,
  quantite     NUMERIC NOT NULL,
  note         TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_inventaire_items_eleveur    ON inventaire_items(uid_eleveur);
CREATE INDEX IF NOT EXISTS idx_inventaire_mouvements_item  ON inventaire_mouvements(item_id);
CREATE INDEX IF NOT EXISTS idx_inventaire_mouvements_elev  ON inventaire_mouvements(uid_eleveur);

-- RLS désactivé : l'app utilise Firebase Auth (pas Supabase Auth) → auth.uid() = null
-- La sécurité est assurée par le filtrage uid_eleveur dans chaque requête côté app.
DROP POLICY IF EXISTS "inventaire_items_eleveur"        ON inventaire_items;
DROP POLICY IF EXISTS "inventaire_items_employe_read"   ON inventaire_items;
DROP POLICY IF EXISTS "inventaire_mouvements_all"       ON inventaire_mouvements;

ALTER TABLE inventaire_items      DISABLE ROW LEVEL SECURITY;
ALTER TABLE inventaire_mouvements DISABLE ROW LEVEL SECURITY;
