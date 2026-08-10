-- Migration : statut "Réservé" pour un animal, avant cession
-- Un chiot réservé garde les infos du futur propriétaire (saisies manuellement
-- ou reprises d'un utilisateur PetsMatch) pour préremplir automatiquement le
-- formulaire de cession — il ne reste alors qu'à saisir la date de départ et
-- valider "Céder". Si l'animal n'a pas été réservé, la cession directe reste
-- inchangée (le formulaire démarre à l'étape "Acquéreur" comme aujourd'hui).

CREATE TABLE IF NOT EXISTS reservations_animaux (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  animal_id             TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  uid_eleveur           TEXT NOT NULL,
  eleveur_profile_id    UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  -- active : réservation en cours, transformee : cédée, annulee : annulée par l'éleveur
  statut                TEXT NOT NULL DEFAULT 'active',
  qualite               TEXT,
  nom                   TEXT,
  email                 TEXT,
  tel                   TEXT,
  adresse               TEXT,
  uid_acquereur         TEXT,
  acquereur_profile_id  UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  date_reservation       DATE,
  notes                 TEXT,
  created_at            TIMESTAMPTZ DEFAULT now(),
  updated_at            TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reservations_animal   ON reservations_animaux(animal_id);
CREATE INDEX IF NOT EXISTS idx_reservations_eleveur   ON reservations_animaux(uid_eleveur);
-- Une seule réservation active à la fois par animal
CREATE UNIQUE INDEX IF NOT EXISTS idx_reservations_animal_active
  ON reservations_animaux(animal_id) WHERE statut = 'active';

ALTER TABLE reservations_animaux ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select reservations" ON reservations_animaux;
DROP POLICY IF EXISTS "Insert reservations" ON reservations_animaux;
DROP POLICY IF EXISTS "Update reservations" ON reservations_animaux;
DROP POLICY IF EXISTS "Delete reservations" ON reservations_animaux;

-- Auth Firebase (pas auth.uid() Supabase) : filtrage applicatif par uid_eleveur,
-- même pattern que les autres tables du projet (ex. enclos_chenil).
CREATE POLICY "Select reservations" ON reservations_animaux
  FOR SELECT USING (true);

CREATE POLICY "Insert reservations" ON reservations_animaux
  FOR INSERT WITH CHECK (uid_eleveur IS NOT NULL AND length(uid_eleveur) > 0);

CREATE POLICY "Update reservations" ON reservations_animaux
  FOR UPDATE USING (true) WITH CHECK (uid_eleveur IS NOT NULL AND length(uid_eleveur) > 0);

CREATE POLICY "Delete reservations" ON reservations_animaux
  FOR DELETE USING (true);
