-- ============================================================
-- PetsMatch — Éducateur/comportementaliste : catalogue unifié
-- (individuel + collectif), lien créneau -> cours, confirmation
-- obligatoire pour un cours collectif, participant manuel.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE prestations_education
  ADD COLUMN IF NOT EXISTS type TEXT NOT NULL DEFAULT 'individuel',
  ADD COLUMN IF NOT EXISTS capacite_max INTEGER; -- utilisé seulement si type='collectif'

ALTER TABLE prestations_education DROP CONSTRAINT IF EXISTS prestations_education_type_check;
ALTER TABLE prestations_education ADD CONSTRAINT prestations_education_type_check
  CHECK (type IN ('individuel', 'collectif'));

ALTER TABLE cours_collectifs
  ADD COLUMN IF NOT EXISTS prestation_id UUID REFERENCES prestations_education(id) ON DELETE SET NULL;

-- Lien optionnel créneau collectif -> cours du catalogue (raccourci "Créer
-- la séance" dans Mes créneaux, pas de génération automatique).
ALTER TABLE creneaux_pro
  ADD COLUMN IF NOT EXISTS prestation_id UUID REFERENCES prestations_education(id) ON DELETE SET NULL;

-- Participant manuel (client sans compte, ajouté par le pro) — même esprit
-- que rdv.client_nom_manuel/client_telephone_manuel.
ALTER TABLE cours_collectifs_participants
  ALTER COLUMN client_uid DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS client_nom_manuel TEXT,
  ADD COLUMN IF NOT EXISTS client_telephone_manuel TEXT;

-- 'demande'    = auto-inscription famille, en attente de confirmation pro (compte dans capacite_max)
-- 'en_attente' = liste d'attente réelle, capacite_max déjà atteint (inchangé)
-- 'inscrit'    = confirmé (par le pro, ou directement si ajouté par le pro/manuel)
ALTER TABLE cours_collectifs_participants DROP CONSTRAINT IF EXISTS cours_collectifs_participants_statut_check;
ALTER TABLE cours_collectifs_participants ADD CONSTRAINT cours_collectifs_participants_statut_check
  CHECK (statut IN ('demande', 'inscrit', 'present', 'absent', 'annule', 'en_attente'));
