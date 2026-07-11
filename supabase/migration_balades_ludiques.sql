-- ============================================================
-- Migration : Balades ludiques (geocaching / chasses au trésor)
-- Module distinct de "promenades" (balades canines collectives)
-- ============================================================

-- ── 1. badges (catalogue générique : badges, trophées, collections) ──────────

CREATE TABLE IF NOT EXISTS badges (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code             TEXT UNIQUE NOT NULL,
  nom              TEXT NOT NULL,
  description      TEXT,
  type             TEXT NOT NULL DEFAULT 'badge' CHECK (type IN ('badge', 'trophee', 'collection')),
  icone_url        TEXT,
  rarete           TEXT DEFAULT 'commun' CHECK (rarete IN ('commun', 'rare', 'epique', 'legendaire')),
  condition_type   TEXT NOT NULL CHECK (condition_type IN (
                      'completion_parcours', 'nb_parcours_completes', 'nb_xp',
                      'createur_note', 'evenement_officiel', 'manuel'
                    )),
  condition_valeur JSONB DEFAULT '{}',
  partenaire_nom   TEXT,
  actif            BOOLEAN DEFAULT TRUE,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE badges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "badges_select" ON badges;
CREATE POLICY "badges_select" ON badges FOR SELECT USING (true);

-- Badges de base (débloqués côté client à la complétion / atteinte de seuils XP)
INSERT INTO badges (code, nom, description, type, icone_url, rarete, condition_type, condition_valeur) VALUES
  ('premiere_balade',     'Première balade',        'Terminer votre premier parcours',            'badge',   '🥾', 'commun',    'nb_parcours_completes', '{"seuil": 1}'),
  ('explorateur_10',      'Explorateur confirmé',   'Terminer 10 parcours',                       'badge',   '🧭', 'rare',      'nb_parcours_completes', '{"seuil": 10}'),
  ('explorateur_50',      'Grand explorateur',      'Terminer 50 parcours',                       'trophee', '🏆', 'epique',    'nb_parcours_completes', '{"seuil": 50}'),
  ('xp_1000',             'Aventurier XP',          'Atteindre 1000 XP',                          'badge',   '⭐', 'rare',      'nb_xp',                 '{"seuil": 1000}'),
  ('createur_premier',    'Créateur de parcours',   'Publier votre premier parcours',             'badge',   '🗺️', 'commun',    'manuel',                '{}'),
  ('createur_bien_note',  'Créateur apprécié',      'Obtenir une note moyenne de 4.5+ sur un parcours', 'trophee', '💎', 'epique', 'createur_note',    '{"seuil": 4.5}')
ON CONFLICT (code) DO NOTHING;

-- ── 2. balades_ludiques (le parcours) ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS balades_ludiques (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  createur_uid         TEXT NOT NULL,
  createur_profile_id  UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  titre                TEXT NOT NULL,
  description          TEXT,
  cover_url            TEXT,
  statut               TEXT NOT NULL DEFAULT 'brouillon' CHECK (statut IN ('brouillon', 'publie', 'desactive', 'supprime')),
  -- Filtres / ciblage
  espece_cible         TEXT DEFAULT 'tous' CHECK (espece_cible IN ('chien', 'chat', 'cheval', 'tous')),
  famille              BOOLEAN DEFAULT FALSE,
  sportif              BOOLEAN DEFAULT FALSE,
  accessible_pmr       BOOLEAN DEFAULT FALSE,
  gratuit              BOOLEAN DEFAULT TRUE,
  prix                 NUMERIC(6,2),
  difficulte           TEXT DEFAULT 'facile' CHECK (difficulte IN ('facile', 'modere', 'difficile')),
  duree_min            INTEGER,
  distance_km          NUMERIC(5,2),
  -- Localisation (point de départ)
  lat_depart           DOUBLE PRECISION NOT NULL,
  lng_depart           DOUBLE PRECISION NOT NULL,
  ville                TEXT,
  departement          TEXT,
  region               TEXT,
  -- Événement temporaire / officiel
  type_evenement       TEXT NOT NULL DEFAULT 'communautaire' CHECK (type_evenement IN ('communautaire', 'officiel_petsmatch', 'officiel_partenaire')),
  partenaire_nom       TEXT,
  event_debut          TIMESTAMPTZ,
  event_fin            TIMESTAMPTZ,
  -- Récompense de complétion
  badge_recompense_id  UUID REFERENCES badges(id) ON DELETE SET NULL,
  xp_recompense        INTEGER DEFAULT 0 CHECK (xp_recompense >= 0),
  -- Stats dénormalisées
  nb_joueurs           INTEGER DEFAULT 0,
  nb_completions       INTEGER DEFAULT 0,
  note_moyenne         NUMERIC(2,1),
  nb_avis              INTEGER DEFAULT 0,
  nb_favoris           INTEGER DEFAULT 0,
  created_at           TIMESTAMPTZ DEFAULT NOW(),
  updated_at           TIMESTAMPTZ DEFAULT NOW(),
  published_at         TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_bl_statut    ON balades_ludiques (statut);
CREATE INDEX IF NOT EXISTS idx_bl_createur  ON balades_ludiques (createur_uid);
CREATE INDEX IF NOT EXISTS idx_bl_createur_profile ON balades_ludiques (createur_profile_id);
CREATE INDEX IF NOT EXISTS idx_bl_geo       ON balades_ludiques (lat_depart, lng_depart);
CREATE INDEX IF NOT EXISTS idx_bl_filtres   ON balades_ludiques (espece_cible, difficulte, gratuit);
CREATE INDEX IF NOT EXISTS idx_bl_event     ON balades_ludiques (type_evenement, event_debut, event_fin);

ALTER TABLE balades_ludiques ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "bl_select" ON balades_ludiques;
CREATE POLICY "bl_select" ON balades_ludiques FOR SELECT USING (true);

DROP POLICY IF EXISTS "bl_insert" ON balades_ludiques;
CREATE POLICY "bl_insert" ON balades_ludiques FOR INSERT WITH CHECK (createur_uid IS NOT NULL);

DROP POLICY IF EXISTS "bl_update" ON balades_ludiques;
CREATE POLICY "bl_update" ON balades_ludiques FOR UPDATE USING (true);

DROP POLICY IF EXISTS "bl_delete" ON balades_ludiques;
CREATE POLICY "bl_delete" ON balades_ludiques FOR DELETE USING (true);

-- ── 3. balades_ludiques_points (étapes / points d'intérêt) ───────────────────

CREATE TABLE IF NOT EXISTS balades_ludiques_points (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  balade_id              UUID NOT NULL REFERENCES balades_ludiques(id) ON DELETE CASCADE,
  ordre                  INTEGER NOT NULL,
  titre                  TEXT NOT NULL,
  description            TEXT,
  lat                    DOUBLE PRECISION NOT NULL,
  lng                    DOUBLE PRECISION NOT NULL,
  rayon_validation_m     INTEGER DEFAULT 30,
  type_defi              TEXT NOT NULL CHECK (type_defi IN ('photo', 'question', 'objet_nature', 'qr_code', 'action_animal', 'gps_seul')),
  question_texte         TEXT,
  question_reponse       TEXT,
  consigne_texte         TEXT,
  qr_code_value          TEXT,
  indice                 TEXT,
  photo_illustration_url TEXT,
  created_at             TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (balade_id, ordre)
);

CREATE INDEX IF NOT EXISTS idx_blp_balade ON balades_ludiques_points (balade_id, ordre);

ALTER TABLE balades_ludiques_points ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "blp_select" ON balades_ludiques_points;
CREATE POLICY "blp_select" ON balades_ludiques_points FOR SELECT USING (true);

DROP POLICY IF EXISTS "blp_insert" ON balades_ludiques_points;
CREATE POLICY "blp_insert" ON balades_ludiques_points FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "blp_update" ON balades_ludiques_points;
CREATE POLICY "blp_update" ON balades_ludiques_points FOR UPDATE USING (true);

DROP POLICY IF EXISTS "blp_delete" ON balades_ludiques_points;
CREATE POLICY "blp_delete" ON balades_ludiques_points FOR DELETE USING (true);

-- ── 4. balades_ludiques_progressions (un joueur sur un parcours) ─────────────

CREATE TABLE IF NOT EXISTS balades_ludiques_progressions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  balade_id           UUID NOT NULL REFERENCES balades_ludiques(id) ON DELETE CASCADE,
  joueur_uid          TEXT NOT NULL,
  joueur_profile_id   UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  statut              TEXT NOT NULL DEFAULT 'en_cours' CHECK (statut IN ('en_cours', 'termine', 'abandonne')),
  nb_points_valides   INTEGER DEFAULT 0,
  started_at          TIMESTAMPTZ DEFAULT NOW(),
  completed_at        TIMESTAMPTZ,
  UNIQUE (balade_id, joueur_profile_id)
);

CREATE INDEX IF NOT EXISTS idx_blpr_joueur ON balades_ludiques_progressions (joueur_uid);
CREATE INDEX IF NOT EXISTS idx_blpr_joueur_profile ON balades_ludiques_progressions (joueur_profile_id);
CREATE INDEX IF NOT EXISTS idx_blpr_balade ON balades_ludiques_progressions (balade_id, statut);

ALTER TABLE balades_ludiques_progressions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "blpr_select" ON balades_ludiques_progressions;
CREATE POLICY "blpr_select" ON balades_ludiques_progressions FOR SELECT USING (true);

DROP POLICY IF EXISTS "blpr_insert" ON balades_ludiques_progressions;
CREATE POLICY "blpr_insert" ON balades_ludiques_progressions FOR INSERT WITH CHECK (joueur_uid IS NOT NULL AND joueur_profile_id IS NOT NULL);

DROP POLICY IF EXISTS "blpr_update" ON balades_ludiques_progressions;
CREATE POLICY "blpr_update" ON balades_ludiques_progressions FOR UPDATE USING (true);

DROP POLICY IF EXISTS "blpr_delete" ON balades_ludiques_progressions;
CREATE POLICY "blpr_delete" ON balades_ludiques_progressions FOR DELETE USING (true);

-- ── 5. balades_ludiques_validations (preuve par étape) ───────────────────────

CREATE TABLE IF NOT EXISTS balades_ludiques_validations (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  progression_id        UUID NOT NULL REFERENCES balades_ludiques_progressions(id) ON DELETE CASCADE,
  point_id              UUID NOT NULL REFERENCES balades_ludiques_points(id) ON DELETE CASCADE,
  joueur_uid            TEXT NOT NULL,
  joueur_profile_id     UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  type_preuve           TEXT NOT NULL CHECK (type_preuve IN ('photo', 'texte', 'gps', 'qr_code')),
  preuve_photo_url      TEXT,
  preuve_texte          TEXT,
  preuve_lat            DOUBLE PRECISION,
  preuve_lng            DOUBLE PRECISION,
  distance_calculee_m   NUMERIC(8,2),
  valide                BOOLEAN NOT NULL DEFAULT TRUE,
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (progression_id, point_id)
);

CREATE INDEX IF NOT EXISTS idx_blv_progression ON balades_ludiques_validations (progression_id);
CREATE INDEX IF NOT EXISTS idx_blv_point       ON balades_ludiques_validations (point_id);

ALTER TABLE balades_ludiques_validations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "blv_select" ON balades_ludiques_validations;
CREATE POLICY "blv_select" ON balades_ludiques_validations FOR SELECT USING (true);

DROP POLICY IF EXISTS "blv_insert" ON balades_ludiques_validations;
CREATE POLICY "blv_insert" ON balades_ludiques_validations FOR INSERT WITH CHECK (joueur_uid IS NOT NULL);

DROP POLICY IF EXISTS "blv_update" ON balades_ludiques_validations;
CREATE POLICY "blv_update" ON balades_ludiques_validations FOR UPDATE USING (true);

DROP POLICY IF EXISTS "blv_delete" ON balades_ludiques_validations;
CREATE POLICY "blv_delete" ON balades_ludiques_validations FOR DELETE USING (true);

-- ── 6. balades_ludiques_avis ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS balades_ludiques_avis (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  balade_id     UUID NOT NULL REFERENCES balades_ludiques(id) ON DELETE CASCADE,
  user_uid      TEXT NOT NULL,
  profile_id    UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  note          INTEGER NOT NULL CHECK (note BETWEEN 1 AND 5),
  commentaire   TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (balade_id, profile_id)
);

CREATE INDEX IF NOT EXISTS idx_bla_balade ON balades_ludiques_avis (balade_id);
CREATE INDEX IF NOT EXISTS idx_bla_profile ON balades_ludiques_avis (profile_id);

ALTER TABLE balades_ludiques_avis ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "bla_select" ON balades_ludiques_avis;
CREATE POLICY "bla_select" ON balades_ludiques_avis FOR SELECT USING (true);

DROP POLICY IF EXISTS "bla_insert" ON balades_ludiques_avis;
CREATE POLICY "bla_insert" ON balades_ludiques_avis FOR INSERT WITH CHECK (user_uid IS NOT NULL AND profile_id IS NOT NULL);

DROP POLICY IF EXISTS "bla_update" ON balades_ludiques_avis;
CREATE POLICY "bla_update" ON balades_ludiques_avis FOR UPDATE USING (true);

DROP POLICY IF EXISTS "bla_delete" ON balades_ludiques_avis;
CREATE POLICY "bla_delete" ON balades_ludiques_avis FOR DELETE USING (true);

-- ── 7. balades_ludiques_favoris ───────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS balades_ludiques_favoris (
  user_uid      TEXT NOT NULL,
  profile_id    UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  balade_id     UUID NOT NULL REFERENCES balades_ludiques(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (profile_id, balade_id)
);

CREATE INDEX IF NOT EXISTS idx_blf_uid ON balades_ludiques_favoris (user_uid);

ALTER TABLE balades_ludiques_favoris ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "blf_select" ON balades_ludiques_favoris;
CREATE POLICY "blf_select" ON balades_ludiques_favoris FOR SELECT USING (true);

DROP POLICY IF EXISTS "blf_insert" ON balades_ludiques_favoris;
CREATE POLICY "blf_insert" ON balades_ludiques_favoris FOR INSERT WITH CHECK (user_uid IS NOT NULL AND profile_id IS NOT NULL);

DROP POLICY IF EXISTS "blf_delete" ON balades_ludiques_favoris;
CREATE POLICY "blf_delete" ON balades_ludiques_favoris FOR DELETE USING (true);

-- ── 8. badges_obtenus ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS badges_obtenus (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_uid      TEXT NOT NULL,
  profile_id    UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  badge_id      UUID NOT NULL REFERENCES badges(id) ON DELETE CASCADE,
  balade_id     UUID REFERENCES balades_ludiques(id) ON DELETE SET NULL,
  obtenu_at     TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (profile_id, badge_id, balade_id)
);

CREATE INDEX IF NOT EXISTS idx_bo_user ON badges_obtenus (user_uid);
CREATE INDEX IF NOT EXISTS idx_bo_profile ON badges_obtenus (profile_id);

ALTER TABLE badges_obtenus ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "bo_select" ON badges_obtenus;
CREATE POLICY "bo_select" ON badges_obtenus FOR SELECT USING (true);

DROP POLICY IF EXISTS "bo_insert" ON badges_obtenus;
CREATE POLICY "bo_insert" ON badges_obtenus FOR INSERT WITH CHECK (user_uid IS NOT NULL AND profile_id IS NOT NULL);

-- ── 9. joueurs_xp (compteur global par joueur) ────────────────────────────────

CREATE TABLE IF NOT EXISTS joueurs_xp (
  profile_id              UUID PRIMARY KEY REFERENCES user_profiles(id) ON DELETE CASCADE,
  user_uid                TEXT NOT NULL,
  xp_total                INTEGER NOT NULL DEFAULT 0,
  nb_parcours_completes   INTEGER NOT NULL DEFAULT 0,
  nb_parcours_crees       INTEGER NOT NULL DEFAULT 0,
  updated_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_xp_total ON joueurs_xp (xp_total DESC);
CREATE INDEX IF NOT EXISTS idx_xp_uid   ON joueurs_xp (user_uid);

ALTER TABLE joueurs_xp ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "xp_select" ON joueurs_xp;
CREATE POLICY "xp_select" ON joueurs_xp FOR SELECT USING (true);

DROP POLICY IF EXISTS "xp_insert" ON joueurs_xp;
CREATE POLICY "xp_insert" ON joueurs_xp FOR INSERT WITH CHECK (user_uid IS NOT NULL AND profile_id IS NOT NULL);

DROP POLICY IF EXISTS "xp_update" ON joueurs_xp;
CREATE POLICY "xp_update" ON joueurs_xp FOR UPDATE USING (true);

-- ── 10. Modération : extension de signalements.target_type ───────────────────

ALTER TABLE signalements DROP CONSTRAINT IF EXISTS signalements_target_type_check;
ALTER TABLE signalements ADD CONSTRAINT signalements_target_type_check
  CHECK (target_type IN ('user', 'annonce', 'profil_pro', 'balade_ludique'));

-- ── 11. Trigger : suppression en cascade des notifications liées ─────────────

CREATE OR REPLACE FUNCTION delete_balade_ludique_notifications()
RETURNS TRIGGER AS $$
BEGIN
  DELETE FROM notifications
  WHERE type IN ('balade_ludique_xp', 'balade_ludique_badge', 'balade_ludique_avis')
    AND data->>'balade_id' = OLD.id::text;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_delete_balade_ludique_notifications ON balades_ludiques;
CREATE TRIGGER trg_delete_balade_ludique_notifications
  BEFORE DELETE ON balades_ludiques
  FOR EACH ROW EXECUTE FUNCTION delete_balade_ludique_notifications();
