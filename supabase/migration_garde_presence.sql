-- ============================================================
-- PetsMatch — Registre légal "garde à domicile" (pet-sitting)
-- Validation de présence pour les gardes-journée (motif 'garde_journee') :
-- une ligne rdv = un jour de garde ; un "séjour" = une suite de jours
-- consécutifs (même client + même animal), regroupée côté appli/site
-- (voir garde_sejour_helper.dart / garde-sejours.ts), pas de nouvelle table.
--
-- arrivee_validee_le : posé sur la ligne du 1er jour du séjour (le pro
--   confirme que l'animal est bien arrivé chez lui).
-- depart_valide_le   : posé sur la ligne du dernier jour (l'animal est
--   reparti). Pour un séjour d'un seul jour, les deux se posent sur
--   l'unique ligne rdv.
--
-- Base légale (garde AVEC hébergement, cf. arrêté du 3 avril 2014) :
-- registre d'entrée et de sortie des animaux obligatoire — contrairement
-- aux promenades/visites à domicile client ("sans hébergement"), qui n'y
-- sont pas soumises (fiche DRAAF "garde sans hébergement / pet-sitting").
--
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE rdv ADD COLUMN IF NOT EXISTS arrivee_validee_le TIMESTAMPTZ;
ALTER TABLE rdv ADD COLUMN IF NOT EXISTS depart_valide_le TIMESTAMPTZ;
