-- Migration : statut des participants promenade
-- Date : 2026-06-23
-- Tickets : PRO11, PRO12, PRO13

ALTER TABLE promenades_participants
  ADD COLUMN IF NOT EXISTS statut TEXT DEFAULT 'accepte';

-- Les participants existants sont déjà validés (default 'accepte')
-- Les nouvelles demandes seront insérées avec statut = 'en_attente'

CREATE INDEX IF NOT EXISTS idx_prom_part_statut ON promenades_participants (promenade_id, statut);
