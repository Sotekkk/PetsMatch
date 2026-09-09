-- ============================================================
-- PetsMatch — Point 2 chevaux : tests génétiques + statut porteur,
-- profil ADN, historique de fertilité / nombre de petits produits.
-- Générique (cheval / chien / chat), aucun gate SQL.
-- Idempotent. SQL Editor Supabase → Run. Relançable.
-- ============================================================

-- 1) Sous-collection « tests génétiques » (pattern carnet de santé)
CREATE TABLE IF NOT EXISTS tests_genetiques (
  id            TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
  animal_id     TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  uid           TEXT,
  profile_id    UUID,
  espece        TEXT,                            -- copie de animaux.espece à la saisie (filtrage presets)
  categorie     TEXT NOT NULL DEFAULT 'maladie', -- 'maladie' | 'adn' | 'robe' | 'aptitude' | 'autre'
  code          TEXT,                            -- clé preset ('WFFS','MDR1'...) ou NULL si saisie libre
  nom           TEXT NOT NULL,
  resultat      TEXT,                            -- 'clair'|'porteur'|'atteint'|'homozygote'|'etabli'|'indetermine'
  genotype      TEXT,                            -- notation labo libre : 'N/N','N/WFFS','HD-A/A','ED-0'
  laboratoire   TEXT,
  date_test     DATE,
  url           TEXT,                            -- PDF/photo, bucket 'media', préfixe 'documents/'
  notes         TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tests_genetiques_animal ON tests_genetiques (animal_id);

ALTER TABLE tests_genetiques ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "tg_all" ON tests_genetiques;
CREATE POLICY "tg_all" ON tests_genetiques FOR ALL USING (true) WITH CHECK (true);

-- 2) Fertilité + raccourci ADN sur animaux (génériques, sans gate SQL)
ALTER TABLE animaux ADD COLUMN IF NOT EXISTS nb_petits_produits   INTEGER;
ALTER TABLE animaux ADD COLUMN IF NOT EXISTS historique_fertilite TEXT;
ALTER TABLE animaux ADD COLUMN IF NOT EXISTS profil_adn_etabli    BOOLEAN DEFAULT FALSE;

-- 3) Override génétique libre sur la saillie (étalon non fiché dans PetsMatch)
ALTER TABLE annonces ADD COLUMN IF NOT EXISTS saillie_genetique TEXT;
