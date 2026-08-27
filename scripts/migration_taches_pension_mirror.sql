-- Permet à une tâche santé (vaccin, vermifuge, antiparasitaire, traitement)
-- d'apparaître aussi dans le calendrier d'une pension ayant un accès actif
-- à la fiche de l'animal, tout en restant visible chez le propriétaire.
--
-- La tâche originale (chez le propriétaire) n'est jamais déplacée : une
-- copie ("miroir") est créée pour la pension, liée à l'originale via
-- origine_tache_id. Quand la pension valide sa copie, l'originale est
-- marquée faite à son tour et le propriétaire reçoit la notification
-- (notify_owner_uid / notify_owner_profile_id portés par la copie).

ALTER TABLE taches_elevage
  ADD COLUMN IF NOT EXISTS origine_tache_id BIGINT REFERENCES taches_elevage(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS notify_owner_uid TEXT,
  ADD COLUMN IF NOT EXISTS notify_owner_profile_id UUID;

CREATE INDEX IF NOT EXISTS idx_taches_elevage_origine_tache_id ON taches_elevage(origine_tache_id);
