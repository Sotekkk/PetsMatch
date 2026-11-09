-- Agenda : un événement créé à la main peut concerner plusieurs animaux
-- (09/11/2026). animal_id garde le premier (compatibilité), animaux_ids la liste.
ALTER TABLE agenda_events
  ADD COLUMN IF NOT EXISTS animaux_ids TEXT[];
