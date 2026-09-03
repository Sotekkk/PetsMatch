-- Co-propriétaires d'un animal (profils particuliers)
-- ============================================================================
-- Un animal de famille : 1 propriétaire PRINCIPAL (référent I-CAD) + N
-- propriétaires SECONDAIRES, tous en accès complet lecture/écriture sur la fiche.
-- Distinct de `partage_animal` (lien lecture seule) et de `animal_access`
-- (accès accordé à un pro avec permissions granulaires).
--
-- Modèle : on étend `animaux_proprietes` (déjà l'historique de propriété).
--   propriétaires courants = date_fin IS NULL AND statut = 'actif'
--   invitation en attente  = statut = 'invite', role_proprio = 'secondaire'
-- ============================================================================

ALTER TABLE animaux_proprietes
  ADD COLUMN IF NOT EXISTS role_proprio TEXT NOT NULL DEFAULT 'principal'
    CHECK (role_proprio IN ('principal','secondaire')),
  ADD COLUMN IF NOT EXISTS statut TEXT NOT NULL DEFAULT 'actif'
    CHECK (statut IN ('actif','invite','refuse')),
  ADD COLUMN IF NOT EXISTS transfert_principal_propose BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS invite_par_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS invite_le    TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS accepte_le   TIMESTAMPTZ;

-- Sécurité avant l'index unique : si des données incohérentes contiennent
-- déjà plusieurs lignes courantes pour un même animal, on ne garde qu'un
-- principal (la plus ancienne) ; les autres passent secondaires.
WITH ranked AS (
  SELECT id, ROW_NUMBER() OVER (
    PARTITION BY animal_id
    ORDER BY date_debut NULLS LAST, created_at, id
  ) AS rn
  FROM animaux_proprietes
  WHERE date_fin IS NULL AND statut = 'actif'
)
UPDATE animaux_proprietes ap
   SET role_proprio = 'secondaire'
  FROM ranked r
 WHERE ap.id = r.id AND r.rn > 1;

-- Un seul principal ACTIF courant par animal.
CREATE UNIQUE INDEX IF NOT EXISTS idx_ap_one_principal
  ON animaux_proprietes (animal_id)
  WHERE date_fin IS NULL AND role_proprio = 'principal' AND statut = 'actif';

CREATE INDEX IF NOT EXISTS idx_ap_animal_actifs
  ON animaux_proprietes (animal_id)
  WHERE date_fin IS NULL AND statut = 'actif';

-- RLS permissive (client Firebase — auth.uid() est NULL, cf.
-- migration_v2_04_fix_rls.sql). Les policies auth.uid() de
-- migration_animaux_proprietes.sql bloqueraient tout.
ALTER TABLE animaux_proprietes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "animaux_proprietes_select" ON animaux_proprietes;
DROP POLICY IF EXISTS "animaux_proprietes_insert" ON animaux_proprietes;
DROP POLICY IF EXISTS "animaux_proprietes_update" ON animaux_proprietes;
DROP POLICY IF EXISTS "firebase_allow_all"        ON animaux_proprietes;
CREATE POLICY "firebase_allow_all" ON animaux_proprietes FOR ALL USING (true) WITH CHECK (true);

-- Transfert atomique du rôle principal (démote l'ancien puis promeut le nouveau,
-- jamais deux principaux en même temps ; met à jour le miroir sur `animaux`).
CREATE OR REPLACE FUNCTION transferer_proprietaire_principal(
  p_animal_id TEXT,
  p_nouveau_profile_id UUID
) RETURNS void AS $$
BEGIN
  UPDATE animaux_proprietes
     SET role_proprio = 'secondaire'
   WHERE animal_id = p_animal_id AND date_fin IS NULL
     AND statut = 'actif' AND role_proprio = 'principal';

  UPDATE animaux_proprietes
     SET role_proprio = 'principal', transfert_principal_propose = false
   WHERE animal_id = p_animal_id AND date_fin IS NULL
     AND statut = 'actif' AND profile_id_proprio = p_nouveau_profile_id;

  UPDATE animaux a
     SET uid_proprietaire = ap.uid_proprio,
         profile_id       = ap.profile_id_proprio
    FROM animaux_proprietes ap
   WHERE ap.animal_id = p_animal_id AND ap.date_fin IS NULL
     AND ap.statut = 'actif' AND ap.role_proprio = 'principal'
     AND a.id = p_animal_id;
END;
$$ LANGUAGE plpgsql;

-- Rétrocompat : toutes les lignes existantes sont des propriétaires uniques
-- → role_proprio='principal', statut='actif' (valeurs par défaut appliquées).
