-- Carnet de santé : nouveau domaine « Chirurgie / Hospitalisation ».
-- Permet de PLANIFIER une intervention (date prévue) avec ses protocoles
-- pré-opératoire (jeûne, prémédication, anesthésie…) et post-opératoire
-- (analgésie, soins de plaie, repos, contrôle…).
-- À exécuter dans l'éditeur SQL Supabase.

CREATE TABLE IF NOT EXISTS chirurgies (
  id                TEXT PRIMARY KEY,
  animal_id         TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  type              TEXT DEFAULT 'chirurgie',   -- 'chirurgie' | 'hospitalisation'
  intitule          TEXT,                        -- ex : « Stérilisation », « Détartrage sous AG »
  date              DATE,                        -- date de l'intervention (prévue ou réalisée)
  statut            TEXT DEFAULT 'prevu',        -- 'prevu' | 'realise' | 'annule'
  protocole_preop   TEXT,
  protocole_postop  TEXT,
  clinique          TEXT,
  veterinaire       TEXT,
  notes             TEXT,
  source            TEXT DEFAULT 'owner',        -- 'owner' | 'veterinaire'
  vet_id            TEXT,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chirurgies_animal ON chirurgies (animal_id);

-- Le compteur de la vignette carnet de santé (_SanteTile) utilise Supabase
-- Realtime (.stream()) — sans ça la vignette reste bloquée sur « Aucune entrée ».
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'chirurgies'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE chirurgies';
  END IF;
END $$;
