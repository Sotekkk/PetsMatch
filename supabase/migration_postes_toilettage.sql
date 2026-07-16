-- ============================================================
-- PetsMatch — Toiletteur : employé/poste assigné au RDV
-- rdv.prestation_id existe déjà (migration_rdv_photographe_columns.sql,
-- FK vers prestations_photographe — colonne réutilisée génériquement,
-- ne référence pas une table précise côté SQL). rdv.employe_id permet le
-- filtrage de conflit par intervenant (rdv_booking_page.dart, flag
-- isToilettage) ; postes_toilettage est prévu pour une gestion multi-
-- postes future (non exploité dans le flux de réservation V1 — décision
-- validée : pas de glisser-déposer, assignation simple par employé
-- suffit pour le MVP).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

CREATE TABLE IF NOT EXISTS postes_toilettage (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  pro_uid        TEXT NOT NULL,
  pro_profile_id UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
  nom            TEXT NOT NULL,
  actif          BOOLEAN NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_postes_toilettage_pro ON postes_toilettage(pro_uid, actif);

ALTER TABLE postes_toilettage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "postes_toilettage_all" ON postes_toilettage;
CREATE POLICY "postes_toilettage_all" ON postes_toilettage FOR ALL USING (true);

ALTER TABLE rdv
  ADD COLUMN IF NOT EXISTS employe_id    BIGINT REFERENCES employes(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS poste_id      UUID REFERENCES postes_toilettage(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS prix_calcule  NUMERIC; -- prix résolu depuis la grille de prix (rdv_booking_page.dart, prixPourAnimal), pré-remplit la facture

CREATE INDEX IF NOT EXISTS idx_rdv_employe ON rdv(employe_id);
CREATE INDEX IF NOT EXISTS idx_rdv_poste ON rdv(poste_id);

-- rdv.prestation_id (migration_rdv_photographe_columns.sql) référençait
-- exclusivement prestations_photographe — colonne réutilisée génériquement
-- ici pour prestations_toilettage aussi. On retire la contrainte FK stricte
-- (elle rejetterait les UUID d'une autre table) au profit d'un simple UUID,
-- cohérent avec le reste du schéma où les colonnes génériques partagées
-- entre profils pro ne sont pas typées vers une table unique.
ALTER TABLE rdv DROP CONSTRAINT IF EXISTS rdv_prestation_id_fkey;
