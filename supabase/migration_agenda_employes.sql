-- Migration : attribution multi-employés + traçabilité validation (agenda)

-- taches_elevage : plusieurs assignés + qui a validé
ALTER TABLE taches_elevage
  ADD COLUMN IF NOT EXISTS assignes_a  TEXT[]     DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS fait_par    TEXT,
  ADD COLUMN IF NOT EXISTS fait_a      TIMESTAMPTZ;

-- plan_taches : valide_at déjà présent, s'assure que valide_par l'est aussi
ALTER TABLE plan_taches
  ADD COLUMN IF NOT EXISTS valide_par  TEXT,
  ADD COLUMN IF NOT EXISTS valide_at   TIMESTAMPTZ;
