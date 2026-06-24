-- ============================================================
-- Migration : Registre mouvements — entrées/sorties multiples
-- Date      : 2026-06-24
-- Un animal = une fiche unique ; N mouvements par propriétaire
-- ============================================================

CREATE TABLE IF NOT EXISTS registre_mouvements (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  animal_id            UUID        NOT NULL,
  uid_eleveur          TEXT        NOT NULL,
  type                 TEXT        NOT NULL CHECK (type IN ('entree', 'sortie')),
  date_mouvement       DATE        NOT NULL,
  motif                TEXT,
  -- Entrée : provenance
  provenance_qualite   TEXT,
  provenance_nom       TEXT,
  provenance_adresse   TEXT,
  -- Sortie : destinataire
  destinataire_qualite TEXT,
  destinataire_nom     TEXT,
  destinataire_adresse TEXT,
  cause_mort           TEXT,
  notes                TEXT,
  -- Lien cession optionnel
  cession_id           UUID,
  created_at           TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reg_mvt_animal  ON registre_mouvements(animal_id);
CREATE INDEX IF NOT EXISTS idx_reg_mvt_eleveur ON registre_mouvements(uid_eleveur);
CREATE INDEX IF NOT EXISTS idx_reg_mvt_date    ON registre_mouvements(date_mouvement);

ALTER TABLE registre_mouvements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "reg_mvt_allow_all" ON registre_mouvements FOR ALL USING (true) WITH CHECK (true);
