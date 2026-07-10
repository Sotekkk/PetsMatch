-- ============================================================
-- PetsMatch — Éducateur/comportementaliste : équipe d'intervenants +
-- temps de trajet à domicile (Phase 2, item 5/5 — dernier volet)
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

-- ─── Équipe d'intervenants ─────────────────────────────────────
-- Un employé (éducateur salarié) peut être assigné à un RDV ou un cours
-- collectif précis, au lieu de toujours supposer que c'est le pro
-- principal qui l'assure. NULL = non assigné (le pro principal assure).

ALTER TABLE rdv
  ADD COLUMN IF NOT EXISTS instructeur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

ALTER TABLE cours_collectifs
  ADD COLUMN IF NOT EXISTS instructeur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_rdv_instructeur ON rdv(instructeur_profile_id);
CREATE INDEX IF NOT EXISTS idx_cours_collectifs_instructeur ON cours_collectifs(instructeur_profile_id);

-- ─── Géocodage du lieu (cours à domicile) ──────────────────────
-- rdv.lieu reste un texte libre (affichage), lat/lng sont dérivées de cette
-- adresse via l'API gratuite api-adresse.data.gouv.fr (déjà utilisée pour
-- l'autocomplete adresse ailleurs dans le projet) pour estimer un temps de
-- trajet à vol d'oiseau entre deux séances à domicile consécutives.

ALTER TABLE rdv
  ADD COLUMN IF NOT EXISTS lieu_lat NUMERIC,
  ADD COLUMN IF NOT EXISTS lieu_lng NUMERIC;
