-- ============================================================
-- PetsMatch — Module Éducateur/Comportementaliste, Phase 1
-- Cours collectifs (plusieurs participants sur un même créneau).
-- Les cours individuels/évaluations continuent d'utiliser la table
-- rdv existante (motifs 'cours_individuel'/'evaluation' déjà gérés
-- par le flux de réservation générique).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS cours_collectifs (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  pro_uid         TEXT NOT NULL,
  pro_profile_id  UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  titre           TEXT NOT NULL,
  date_heure      TIMESTAMPTZ NOT NULL,
  duree_minutes   INTEGER NOT NULL DEFAULT 90,
  capacite_max    INTEGER NOT NULL DEFAULT 6,
  lieu            TEXT, -- adresse ou "chez le pro" / "à domicile"
  notes           TEXT,
  statut          TEXT NOT NULL DEFAULT 'planifie'
                    CHECK (statut IN ('planifie', 'annule', 'termine')),
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cours_collectifs_pro ON cours_collectifs(pro_uid, date_heure);

ALTER TABLE cours_collectifs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select cours_collectifs" ON cours_collectifs;
CREATE POLICY "Select cours_collectifs" ON cours_collectifs FOR SELECT USING (true);

DROP POLICY IF EXISTS "Insert cours_collectifs" ON cours_collectifs;
CREATE POLICY "Insert cours_collectifs" ON cours_collectifs
  FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND length(pro_uid) > 0);

DROP POLICY IF EXISTS "Update cours_collectifs" ON cours_collectifs;
CREATE POLICY "Update cours_collectifs" ON cours_collectifs FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Delete cours_collectifs" ON cours_collectifs;
CREATE POLICY "Delete cours_collectifs" ON cours_collectifs FOR DELETE USING (true);

-- ─── Participants d'un cours collectif ───────────────────────

CREATE TABLE IF NOT EXISTS cours_collectifs_participants (
  id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  cours_id          UUID NOT NULL REFERENCES cours_collectifs(id) ON DELETE CASCADE,
  client_uid        TEXT NOT NULL,
  client_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  animal_id         TEXT REFERENCES animaux(id) ON DELETE SET NULL,
  statut            TEXT NOT NULL DEFAULT 'inscrit'
                       CHECK (statut IN ('inscrit', 'present', 'absent', 'annule')),
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (cours_id, client_uid, animal_id)
);

CREATE INDEX IF NOT EXISTS idx_cours_participants_cours ON cours_collectifs_participants(cours_id);
CREATE INDEX IF NOT EXISTS idx_cours_participants_client ON cours_collectifs_participants(client_uid);

ALTER TABLE cours_collectifs_participants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select cours_participants" ON cours_collectifs_participants;
CREATE POLICY "Select cours_participants" ON cours_collectifs_participants FOR SELECT USING (true);

DROP POLICY IF EXISTS "Insert cours_participants" ON cours_collectifs_participants;
CREATE POLICY "Insert cours_participants" ON cours_collectifs_participants
  FOR INSERT WITH CHECK (client_uid IS NOT NULL AND length(client_uid) > 0);

DROP POLICY IF EXISTS "Update cours_participants" ON cours_collectifs_participants;
CREATE POLICY "Update cours_participants" ON cours_collectifs_participants FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Delete cours_participants" ON cours_collectifs_participants;
CREATE POLICY "Delete cours_participants" ON cours_collectifs_participants FOR DELETE USING (true);

-- ─── Tarifs éducateur par type de prestation ─────────────────
-- Réutilise le même modèle que pension (tarifs_logements JSONB) :
-- { "cours_individuel": 45, "cours_collectif": 20, "evaluation": 60, "domicile_supplement": 15 }

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS tarifs_education JSONB DEFAULT '{}'::jsonb;

-- ─── Suivi de progression (education_progression) ─────────────
-- Table déjà utilisée par pro_clients_page.dart (_addProgression) — on
-- s'assure juste que les colonnes attendues existent (idempotent), pas de
-- nouvelle table créée pour éviter tout doublon avec l'existant.

ALTER TABLE education_progression
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
