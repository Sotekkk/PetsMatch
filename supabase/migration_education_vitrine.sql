-- ============================================================
-- PetsMatch — Éducateur/comportementaliste : vitrine publique
-- (galerie + tarifs affichables + description du bilan)
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

-- ─── Profil ──────────────────────────────────────────────────
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS tarifs_education_visibles   BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS tarifs_education_extra      JSONB   DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS education_bilan_description TEXT;

-- tarifs_education_visibles : opt-in — tant que false, la vitrine est inchangée.
-- tarifs_education_extra    : prestations libres nommées par l'éducateur,
--   [{ "label": "École du chiot", "prix": 25, "description": "…" }]
--   (les 4 prestations canoniques restent dans tarifs_education).
-- education_bilan_description : décrit le bilan imposé au 1er RDV
--   (affiché sur la fiche publique + à la réservation quand education_bilan_requis).

-- ─── Forfaits (packs de séances) ─────────────────────────────
-- Visibilité sur la fiche publique, au choix, forfait par forfait
-- (toujours soumis à user_profiles.tarifs_education_visibles).
ALTER TABLE forfaits_education
  ADD COLUMN IF NOT EXISTS affiche_public BOOLEAN DEFAULT false;
