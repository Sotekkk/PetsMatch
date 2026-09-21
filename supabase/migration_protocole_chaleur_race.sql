-- Protocole de chaleur par race : un éleveur peut définir un intervalle de
-- chaleurs (en jours) propre à une race qu'il élève (ex. Pomsky = 120j),
-- plutôt que de dépendre uniquement de la moyenne par espèce ou de le
-- régler animal par animal. Ordre de résolution partout où l'intervalle
-- est utilisé : override par animal (animaux.intervalle_chaleurs_jours)
-- > protocole race (cette table) > défaut par espèce (codé en dur).
-- Comme le reste du projet, pas de RLS restrictive (Firebase Auth + client
-- anon Supabase, auth.uid() inexploitable) : filtrage applicatif par uid_eleveur.

CREATE TABLE IF NOT EXISTS protocoles_chaleur_race (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid_eleveur      TEXT NOT NULL,
  espece           TEXT NOT NULL,
  race             TEXT NOT NULL,
  intervalle_jours INTEGER NOT NULL CHECK (intervalle_jours > 0),
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (uid_eleveur, espece, race)
);

CREATE INDEX IF NOT EXISTS idx_protocoles_chaleur_race_uid
  ON protocoles_chaleur_race (uid_eleveur);

ALTER TABLE protocoles_chaleur_race ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "protocoles_chaleur_race_select" ON protocoles_chaleur_race;
CREATE POLICY "protocoles_chaleur_race_select" ON protocoles_chaleur_race FOR SELECT USING (true);

DROP POLICY IF EXISTS "protocoles_chaleur_race_insert" ON protocoles_chaleur_race;
CREATE POLICY "protocoles_chaleur_race_insert" ON protocoles_chaleur_race FOR INSERT WITH CHECK (uid_eleveur IS NOT NULL);

DROP POLICY IF EXISTS "protocoles_chaleur_race_update" ON protocoles_chaleur_race;
CREATE POLICY "protocoles_chaleur_race_update" ON protocoles_chaleur_race FOR UPDATE USING (true);

DROP POLICY IF EXISTS "protocoles_chaleur_race_delete" ON protocoles_chaleur_race;
CREATE POLICY "protocoles_chaleur_race_delete" ON protocoles_chaleur_race FOR DELETE USING (true);
