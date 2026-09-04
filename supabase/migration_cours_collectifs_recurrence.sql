-- ============================================================
-- PetsMatch — Éducateur : cours collectifs récurrents + liste d'attente
-- Une "série" génère des occurrences hebdomadaires dans cours_collectifs
-- (colonne serie_id) sur un horizon glissant, entretenu par la Cloud
-- Function generateCoursCollectifsOccurrences (functions/agenda.js).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS cours_collectifs_series (
  id                      UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  pro_uid                 TEXT NOT NULL,
  pro_profile_id          UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  titre                   TEXT NOT NULL,
  date_debut              TIMESTAMPTZ NOT NULL, -- 1ère occurrence (date + heure) ; jour de semaine + heure se répètent chaque semaine
  duree_minutes           INTEGER NOT NULL DEFAULT 90,
  capacite_max            INTEGER NOT NULL DEFAULT 6,
  lieu                    TEXT,
  notes                   TEXT,
  instructeur_profile_id  UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  date_fin                DATE, -- NULL = pas de date de fin (jusqu'à annulation par le pro)
  statut                  TEXT NOT NULL DEFAULT 'actif' CHECK (statut IN ('actif', 'annule')),
  created_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cours_collectifs_series_pro ON cours_collectifs_series(pro_uid, statut);

ALTER TABLE cours_collectifs_series ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select cours_collectifs_series" ON cours_collectifs_series;
CREATE POLICY "Select cours_collectifs_series" ON cours_collectifs_series FOR SELECT USING (true);

DROP POLICY IF EXISTS "Insert cours_collectifs_series" ON cours_collectifs_series;
CREATE POLICY "Insert cours_collectifs_series" ON cours_collectifs_series
  FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND length(pro_uid) > 0);

DROP POLICY IF EXISTS "Update cours_collectifs_series" ON cours_collectifs_series;
CREATE POLICY "Update cours_collectifs_series" ON cours_collectifs_series FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Delete cours_collectifs_series" ON cours_collectifs_series;
CREATE POLICY "Delete cours_collectifs_series" ON cours_collectifs_series FOR DELETE USING (true);

-- ─── Lien occurrence -> série ──────────────────────────────────

ALTER TABLE cours_collectifs
  ADD COLUMN IF NOT EXISTS serie_id UUID REFERENCES cours_collectifs_series(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_cours_collectifs_serie ON cours_collectifs(serie_id);

-- ─── Inscription "à toute la série" + liste d'attente ──────────
-- serie_id renseigné = inscription portée automatiquement d'une occurrence à
-- l'autre par generateCoursCollectifsOccurrences ; NULL = inscription
-- ponctuelle à cette seule occurrence (comportement existant inchangé).

ALTER TABLE cours_collectifs_participants
  ADD COLUMN IF NOT EXISTS serie_id UUID REFERENCES cours_collectifs_series(id) ON DELETE SET NULL;

ALTER TABLE cours_collectifs_participants
  DROP CONSTRAINT IF EXISTS cours_collectifs_participants_statut_check;
ALTER TABLE cours_collectifs_participants
  ADD CONSTRAINT cours_collectifs_participants_statut_check
  CHECK (statut IN ('inscrit', 'present', 'absent', 'annule', 'en_attente'));
