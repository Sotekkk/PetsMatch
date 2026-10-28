-- ============================================================
-- PetsMatch — Plusieurs animaux sur un même RDV (vétérinaire, ostéo,
-- toiletteur, éducateur) : chaque animal a son motif et sa durée.
-- rdv.animal_id reste le premier animal, rdv.animaux_ids la liste complète,
-- rdv.duree_minutes la somme des durées ; animaux_detail porte le détail :
--   [{ "id", "nom", "motif", "motif_cle", "duree_minutes", "prestation_id", "prix" }]
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE rdv
  ADD COLUMN IF NOT EXISTS animaux_ids JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS animaux_detail JSONB;
