-- Protocoles : heure précise et employé attribué par étape (09/11/2026).
-- « Distribution des repas à 10 h », attribuée à un employé : chaque tâche
-- générée porte l'heure (plan_taches.heure) et l'employé (assigned_to /
-- assigned_profile_id). Colonnes envoyées seulement quand elles sont remplies.

ALTER TABLE plan_template_etapes
  ADD COLUMN IF NOT EXISTS heure              TEXT,   -- 'HH:MM'
  ADD COLUMN IF NOT EXISTS assigne_uid        TEXT,   -- employé (uid Firebase)
  ADD COLUMN IF NOT EXISTS assigne_profile_id UUID;   -- son profil employé

ALTER TABLE plan_taches
  ADD COLUMN IF NOT EXISTS heure TEXT;
