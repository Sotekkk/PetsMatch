-- ============================================================
-- PetsMatch — Éducateur/comportementaliste : forfaits + tarification
-- automatisée des cours collectifs (Phase 2, item 2/5)
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

-- ─── Forfaits (packs de séances) ──────────────────────────────
-- Catalogue informatif défini par le pro — pas de suivi de crédit/solde
-- automatisé pour l'instant (même logique que tarifs_education :
-- affichage + facturation manuelle, pas de paiement in-app pro↔client).

CREATE TABLE IF NOT EXISTS forfaits_education (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  pro_uid         TEXT NOT NULL,
  pro_profile_id  UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
  nom             TEXT NOT NULL,
  nb_seances      INTEGER NOT NULL DEFAULT 1,
  prix            NUMERIC NOT NULL DEFAULT 0,
  description     TEXT,
  actif           BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_forfaits_education_pro ON forfaits_education(pro_uid, actif);

ALTER TABLE forfaits_education ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Select forfaits_education" ON forfaits_education;
CREATE POLICY "Select forfaits_education" ON forfaits_education FOR SELECT USING (true);

DROP POLICY IF EXISTS "Insert forfaits_education" ON forfaits_education;
CREATE POLICY "Insert forfaits_education" ON forfaits_education
  FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND length(pro_uid) > 0);

DROP POLICY IF EXISTS "Update forfaits_education" ON forfaits_education;
CREATE POLICY "Update forfaits_education" ON forfaits_education FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Delete forfaits_education" ON forfaits_education;
CREATE POLICY "Delete forfaits_education" ON forfaits_education FOR DELETE USING (true);

-- ─── Tarification automatisée des cours collectifs ────────────
-- Prix figé au moment de l'inscription (dérivé de tarifs_education au
-- moment T), pour référence/facturation, même si le pro change ses
-- tarifs plus tard.

ALTER TABLE cours_collectifs_participants
  ADD COLUMN IF NOT EXISTS prix NUMERIC;
