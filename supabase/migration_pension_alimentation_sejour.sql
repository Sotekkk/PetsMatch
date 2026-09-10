-- ============================================================
-- PetsMatch — Alimentation fournie POUR CE SÉJOUR en pension
-- (équidés / animaux de la ferme surtout : foin / granulés / compléments).
--
-- Distinct de la table `alimentations` (régime habituel, clé animal_id,
-- maintenu par le PROPRIÉTAIRE) : ici c'est ce que LA PENSION assure pendant
-- ce séjour précis. NULL pour la grande majorité des séjours (chien / chat).
--
-- Forme du JSON :
--   { "fournis_par": "pension" | "proprietaire" | "mixte",
--     "foin": text, "granules": text, "complements": text,
--     "autres": text, "consignes": text }
--
-- Idempotent. Supabase SQL Editor → Run. Relançable.
-- ============================================================

ALTER TABLE pension_entrees
  ADD COLUMN IF NOT EXISTS alimentation_sejour JSONB;
