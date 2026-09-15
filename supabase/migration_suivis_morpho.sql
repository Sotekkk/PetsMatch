-- ============================================================
-- PetsMatch — Suivi morphologique & bien-être (chien/chat)
-- Carnet d'observations postural/morphologique dans le temps :
-- photos de référence, silhouette anatomique par zones nommées,
-- observations statiques/dynamiques. Distinct de seances_osteo/
-- points_osteo (points de tension libres posés au tap) — coexistent,
-- ne pas fusionner sans décision produit explicite.
-- Exécuter dans Supabase SQL Editor (idempotent).
-- ============================================================

-- ─── 1. En-tête d'un suivi ───────────────────────────────────
CREATE TABLE IF NOT EXISTS suivis_morpho (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  animal_id         TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  uid_auteur        TEXT NOT NULL,
  pro_profile_id    UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  type_suivi        TEXT NOT NULL DEFAULT 'autre',
    -- bilan_morphologique | bilan_posture | osteopathie | physiotherapie |
    -- suivi_veterinaire | suivi_sportif | suivi_post_operatoire | prevention | autre
  date              DATE NOT NULL DEFAULT CURRENT_DATE,
  professionnel_nom TEXT,
  motif             TEXT,
  commentaires      TEXT,
  poids             NUMERIC(6,3),
  taille            NUMERIC(6,2),
  age_mois          INT,
  niveau_activite   TEXT,   -- faible | moderee | elevee | non_evalue
  activite_sportive TEXT,
  checkpoint_age    TEXT,   -- libellé libre éleveur : "naissance", "8 semaines"...
  source            TEXT NOT NULL DEFAULT 'proprietaire'
    CHECK (source IN ('proprietaire','mesure','professionnel')),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_suivis_morpho_animal ON suivis_morpho(animal_id);
CREATE INDEX IF NOT EXISTS idx_suivis_morpho_date    ON suivis_morpho(animal_id, date DESC);

-- ─── 2. Photos (4 vues guidées + extra + zoom sur zone) ──────
CREATE TABLE IF NOT EXISTS suivis_morpho_photos (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  suivi_id   UUID NOT NULL REFERENCES suivis_morpho(id) ON DELETE CASCADE,
  vue        TEXT NOT NULL,   -- face | dos | profil_g | profil_d | zone | autre
  zone       TEXT,            -- clé de zone si vue = 'zone'
  url        TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_suivis_morpho_photos_suivi ON suivis_morpho_photos(suivi_id);

-- ─── 3. Vidéos ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS suivis_morpho_videos (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  suivi_id    UUID NOT NULL REFERENCES suivis_morpho(id) ON DELETE CASCADE,
  activite    TEXT,   -- marche | trot | course | escaliers | assis_debout | sport | autre
  commentaire TEXT,
  url         TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_suivis_morpho_videos_suivi ON suivis_morpho_videos(suivi_id);

-- ─── 4. Zones anatomiques (silhouette interactive) ───────────
CREATE TABLE IF NOT EXISTS suivis_morpho_zones (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  suivi_id     UUID NOT NULL REFERENCES suivis_morpho(id) ON DELETE CASCADE,
  zone         TEXT NOT NULL,
    -- tete, cervicales, epaule_g, epaule_d, coude_g, coude_d, carpe_g, carpe_d,
    -- patte_anterieure_g, patte_anterieure_d, colonne, bassin, hanche_g, hanche_d,
    -- genou_g, genou_d, jarret_g, jarret_d, patte_posterieure_g, patte_posterieure_d
  sensibilite  TEXT NOT NULL DEFAULT 'non_evaluee'
    CHECK (sensibilite IN ('non','oui','non_evaluee')),
  mobilite     TEXT NOT NULL DEFAULT 'non_evaluee'
    CHECK (mobilite IN ('normale','limitee','augmentee','non_evaluee')),
  commentaire  TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_suivis_morpho_zones_suivi ON suivis_morpho_zones(suivi_id);

-- ─── 5. Observations statiques (posture) ─────────────────────
CREATE TABLE IF NOT EXISTS suivis_morpho_observations (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  suivi_id    UUID NOT NULL REFERENCES suivis_morpho(id) ON DELETE CASCADE,
  categorie   TEXT NOT NULL,
    -- aplombs_anterieurs, aplombs_posterieurs, symetrie, ligne_dos,
    -- position_bassin, position_membres, autre
  valeur      TEXT NOT NULL DEFAULT 'non_evalue'
    CHECK (valeur IN ('normal','a_surveiller','non_evalue')),
  commentaire TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_suivis_morpho_observations_suivi ON suivis_morpho_observations(suivi_id);

-- ─── 6. Observations dynamiques (mouvement) ──────────────────
CREATE TABLE IF NOT EXISTS suivis_morpho_mouvements (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  suivi_id       UUID NOT NULL REFERENCES suivis_morpho(id) ON DELETE CASCADE,
  activite       TEXT NOT NULL,
    -- marche | trot | course | assis_debout | escaliers | saut | sport | autre
  observation    TEXT,
  gene_observee  BOOLEAN,
  commentaire    TEXT,
  video_id       UUID REFERENCES suivis_morpho_videos(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_suivis_morpho_mouvements_suivi ON suivis_morpho_mouvements(suivi_id);

-- ─── RLS — même convention permissive que points_osteo/animal_access,
-- contrôle d'accès fait côté application (animaux_proprietes / uid_eleveur /
-- animal_access.permissions contenant read_morpho / write_morpho). ────────
ALTER TABLE suivis_morpho              ENABLE ROW LEVEL SECURITY;
ALTER TABLE suivis_morpho_photos       ENABLE ROW LEVEL SECURITY;
ALTER TABLE suivis_morpho_videos       ENABLE ROW LEVEL SECURITY;
ALTER TABLE suivis_morpho_zones        ENABLE ROW LEVEL SECURITY;
ALTER TABLE suivis_morpho_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE suivis_morpho_mouvements   ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "suivis_morpho_anon" ON suivis_morpho;
CREATE POLICY "suivis_morpho_anon" ON suivis_morpho FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "suivis_morpho_photos_anon" ON suivis_morpho_photos;
CREATE POLICY "suivis_morpho_photos_anon" ON suivis_morpho_photos FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "suivis_morpho_videos_anon" ON suivis_morpho_videos;
CREATE POLICY "suivis_morpho_videos_anon" ON suivis_morpho_videos FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "suivis_morpho_zones_anon" ON suivis_morpho_zones;
CREATE POLICY "suivis_morpho_zones_anon" ON suivis_morpho_zones FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "suivis_morpho_observations_anon" ON suivis_morpho_observations;
CREATE POLICY "suivis_morpho_observations_anon" ON suivis_morpho_observations FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "suivis_morpho_mouvements_anon" ON suivis_morpho_mouvements;
CREATE POLICY "suivis_morpho_mouvements_anon" ON suivis_morpho_mouvements FOR ALL USING (true) WITH CHECK (true);

-- Compteur de vignette (même mécanisme que chirurgies) via Realtime.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'suivis_morpho'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE suivis_morpho';
  END IF;
END $$;
