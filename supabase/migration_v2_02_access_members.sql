-- ============================================================
-- PetsMatch V2 — Phase 2 : animal_access + profile_members
--   + colonnes profile_id sur toutes les tables domaine
-- Exécuter APRÈS migration_v2_01_user_profiles.sql
-- ============================================================

-- ─── 1. TABLE animal_access ─────────────────────────────────
-- Remplace : vet_access_grants + pension_acces + pro_animal_access
-- Même comportement : pending → active → revoked

CREATE TABLE IF NOT EXISTS animal_access (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  animal_id             TEXT NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  pro_profile_id        UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  granted_by_profile_id UUID NOT NULL REFERENCES user_profiles(id),
  permissions           TEXT[] NOT NULL DEFAULT '{read_basic}',
  -- Permissions disponibles :
  --   read_basic       : nom, espèce, race, photo, contacts urgence
  --   read_health      : carnet santé, vaccins, traitements, antécédents
  --   read_alimentation: régime alimentaire, quantités, fréquences
  --   write_health     : ajouter consultations, actes, ordonnances
  --   write_notes      : journal séjour, rapport sortie/promenade
  --   write_behavior   : suivi comportemental, séances éducation
  --   write_farriery   : fiche ferrage (maréchal-ferrant)
  statut                TEXT NOT NULL DEFAULT 'pending'
                        CHECK (statut IN ('pending','active','revoked')),
  granted_at            TIMESTAMPTZ,
  revoked_at            TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (animal_id, pro_profile_id)
);

ALTER TABLE animal_access ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "animal_access_anon" ON animal_access;
CREATE POLICY "animal_access_anon" ON animal_access FOR ALL USING (true) WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_animal_access_animal   ON animal_access (animal_id);
CREATE INDEX IF NOT EXISTS idx_animal_access_pro      ON animal_access (pro_profile_id);
CREATE INDEX IF NOT EXISTS idx_animal_access_statut   ON animal_access (statut);

-- ─── 2. Migrer vet_access_grants → animal_access ────────────

INSERT INTO animal_access (
  animal_id, pro_profile_id, granted_by_profile_id,
  permissions, statut, granted_at, created_at
)
SELECT
  v.animal_id,
  COALESCE(
    (SELECT up.id FROM user_profiles up WHERE up.uid = v.vet_id AND up.is_main = TRUE LIMIT 1),
    (SELECT up.id FROM user_profiles up WHERE up.uid = v.vet_id LIMIT 1)
  ) AS pro_profile_id,
  COALESCE(
    (SELECT up.id FROM user_profiles up WHERE up.uid = a.uid_eleveur AND up.is_main = TRUE LIMIT 1),
    (SELECT up.id FROM user_profiles up WHERE up.uid = a.uid_eleveur LIMIT 1)
  ) AS granted_by_profile_id,
  ARRAY['read_basic','read_health','write_health'] AS permissions,
  CASE v.status
    WHEN 'active'  THEN 'active'
    WHEN 'revoked' THEN 'revoked'
    ELSE 'pending'
  END,
  v.granted_at,
  COALESCE(v.granted_at, NOW())
FROM vet_access_grants v
JOIN animaux a ON a.id = v.animal_id
WHERE EXISTS (
  SELECT 1 FROM user_profiles up WHERE up.uid = v.vet_id
)
ON CONFLICT (animal_id, pro_profile_id) DO NOTHING;

-- ─── 3. Migrer pension_acces → animal_access ────────────────

INSERT INTO animal_access (
  animal_id, pro_profile_id, granted_by_profile_id,
  permissions, statut, granted_at, created_at
)
SELECT
  p.animal_id,
  COALESCE(
    (SELECT up.id FROM user_profiles up WHERE up.uid = p.pro_uid AND up.is_main = TRUE LIMIT 1),
    (SELECT up.id FROM user_profiles up WHERE up.uid = p.pro_uid LIMIT 1)
  ) AS pro_profile_id,
  COALESCE(
    (SELECT up.id FROM user_profiles up WHERE up.uid = a.uid_eleveur AND up.is_main = TRUE LIMIT 1),
    (SELECT up.id FROM user_profiles up WHERE up.uid = a.uid_eleveur LIMIT 1)
  ) AS granted_by_profile_id,
  -- Pension : read_basic + write_notes + read_alimentation par défaut
  ARRAY['read_basic','write_notes','read_alimentation'] AS permissions,
  CASE p.statut
    WHEN 'approved' THEN 'active'
    WHEN 'revoked'  THEN 'revoked'
    ELSE 'pending'
  END,
  NULL,   -- granted_at (pas de colonne équivalente dans pension_acces)
  NOW()
FROM pension_acces p
JOIN animaux a ON a.id = p.animal_id
WHERE EXISTS (
  SELECT 1 FROM user_profiles up WHERE up.uid = p.pro_uid
)
ON CONFLICT (animal_id, pro_profile_id) DO NOTHING;

-- ─── 4. source_profile_id sur tables de santé ───────────────
-- Remplace vet_id TEXT → source_profile_id UUID
-- Couvre vétérinaire ET pension (write_health sur demande)

ALTER TABLE vaccinations
  ADD COLUMN IF NOT EXISTS source_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;
ALTER TABLE traitements
  ADD COLUMN IF NOT EXISTS source_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;
ALTER TABLE visites
  ADD COLUMN IF NOT EXISTS source_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;
ALTER TABLE vermifuges
  ADD COLUMN IF NOT EXISTS source_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;
ALTER TABLE antiparasitaires
  ADD COLUMN IF NOT EXISTS source_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

-- Backfill : relier les entrées existantes avec vet_id → user_profiles.id
UPDATE vaccinations v
SET source_profile_id = up.id
FROM user_profiles up
WHERE up.uid = v.vet_id AND up.is_main = TRUE
  AND v.vet_id IS NOT NULL AND v.source_profile_id IS NULL;

UPDATE traitements v
SET source_profile_id = up.id
FROM user_profiles up
WHERE up.uid = v.vet_id AND up.is_main = TRUE
  AND v.vet_id IS NOT NULL AND v.source_profile_id IS NULL;

UPDATE visites v
SET source_profile_id = up.id
FROM user_profiles up
WHERE up.uid = v.vet_id AND up.is_main = TRUE
  AND v.vet_id IS NOT NULL AND v.source_profile_id IS NULL;

UPDATE vermifuges v
SET source_profile_id = up.id
FROM user_profiles up
WHERE up.uid = v.vet_id AND up.is_main = TRUE
  AND v.vet_id IS NOT NULL AND v.source_profile_id IS NULL;

UPDATE antiparasitaires v
SET source_profile_id = up.id
FROM user_profiles up
WHERE up.uid = v.vet_id AND up.is_main = TRUE
  AND v.vet_id IS NOT NULL AND v.source_profile_id IS NULL;

-- ─── 5. TABLE profile_members ────────────────────────────────
-- Employés / bénévoles / familles d'accueil d'une organisation

CREATE TABLE IF NOT EXISTS profile_members (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_profile_id    UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  member_profile_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  role              TEXT NOT NULL CHECK (role IN (
                      'manager','employe','benevole','famille_accueil'
                    )),
  permissions       TEXT[] NOT NULL DEFAULT '{}',
  -- Permissions disponibles :
  --   read_animaux     : voir les fiches animaux de l'organisation
  --   write_animaux    : modifier les fiches animaux
  --   write_animaux_basic : modifications limitées (rapport, notes)
  --   read_agenda      : voir l'agenda
  --   write_agenda     : gérer l'agenda
  --   read_taches      : voir les tâches
  --   write_taches     : créer/compléter des tâches
  --   read_contrats    : voir les contrats
  --   write_contrats   : créer des contrats
  --   manage_members   : gérer les membres (inviter, retirer)
  --   manage_finance   : accès comptabilité et abonnements
  statut            TEXT NOT NULL DEFAULT 'invite'
                    CHECK (statut IN ('invite','actif','inactif')),
  date_debut        DATE,
  date_fin          DATE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (org_profile_id, member_profile_id)
);

ALTER TABLE profile_members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "profile_members_anon" ON profile_members;
CREATE POLICY "profile_members_anon" ON profile_members FOR ALL USING (true) WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_profile_members_org    ON profile_members (org_profile_id);
CREATE INDEX IF NOT EXISTS idx_profile_members_member ON profile_members (member_profile_id);

-- ─── 6. Migrer employes existants → profile_members ─────────

-- La table employes existante a : uid (employeur), employee_uid, role_employe, permissions
INSERT INTO profile_members (
  org_profile_id, member_profile_id, role, permissions, statut, created_at
)
SELECT
  COALESCE(
    (SELECT up.id FROM user_profiles up WHERE up.uid = e.uid_eleveur AND up.is_main = TRUE LIMIT 1),
    (SELECT up.id FROM user_profiles up WHERE up.uid = e.uid_eleveur LIMIT 1)
  ) AS org_profile_id,
  COALESCE(
    (SELECT up.id FROM user_profiles up WHERE up.uid = e.uid_employe AND up.is_main = TRUE LIMIT 1),
    (SELECT up.id FROM user_profiles up WHERE up.uid = e.uid_employe LIMIT 1)
  ) AS member_profile_id,
  CASE e.type
    WHEN 'admin'    THEN 'manager'
    WHEN 'manager'  THEN 'manager'
    WHEN 'soigneur' THEN 'employe'
    WHEN 'benevole' THEN 'benevole'
    ELSE 'employe'
  END AS role,
  ARRAY['read_animaux','read_agenda','write_taches'],
  CASE WHEN COALESCE(e.actif, TRUE) THEN 'actif' ELSE 'inactif' END,
  NOW()
FROM employes e
WHERE e.uid_employe IS NOT NULL
  AND EXISTS (SELECT 1 FROM user_profiles up WHERE up.uid = e.uid_eleveur)
  AND EXISTS (SELECT 1 FROM user_profiles up WHERE up.uid = e.uid_employe)
ON CONFLICT (org_profile_id, member_profile_id) DO NOTHING;

-- Migrer familles d'accueil (table familles_accueil)
INSERT INTO profile_members (
  org_profile_id, member_profile_id, role, permissions, statut, created_at
)
SELECT
  COALESCE(
    (SELECT up.id FROM user_profiles up WHERE up.uid = fa.association_uid AND up.is_main = TRUE LIMIT 1),
    (SELECT up.id FROM user_profiles up WHERE up.uid = fa.association_uid LIMIT 1)
  ) AS org_profile_id,
  COALESCE(
    (SELECT up.id FROM user_profiles up WHERE up.uid = fa.fa_uid AND up.is_main = TRUE LIMIT 1),
    (SELECT up.id FROM user_profiles up WHERE up.uid = fa.fa_uid LIMIT 1)
  ) AS member_profile_id,
  'famille_accueil' AS role,
  ARRAY['read_animaux','write_animaux_basic','read_agenda'] AS permissions,
  CASE WHEN COALESCE(fa.actif, TRUE) THEN 'actif' ELSE 'inactif' END,
  COALESCE(fa.created_at, NOW())
FROM familles_accueil fa
WHERE fa.fa_uid IS NOT NULL
  AND EXISTS (SELECT 1 FROM user_profiles up WHERE up.uid = fa.association_uid)
  AND EXISTS (SELECT 1 FROM user_profiles up WHERE up.uid = fa.fa_uid)
ON CONFLICT (org_profile_id, member_profile_id) DO NOTHING;

-- ─── 7. Colonnes profile_id sur animaux ─────────────────────

ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS profile_id_eleveur   UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS profile_id_acquereur UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

-- Backfill éleveur
UPDATE animaux a
SET profile_id_eleveur = up.id
FROM user_profiles up
WHERE up.uid = a.uid_eleveur
  AND up.is_main = TRUE
  AND a.profile_id_eleveur IS NULL;

-- Backfill acquéreur
UPDATE animaux a
SET profile_id_acquereur = up.id
FROM user_profiles up
WHERE up.uid = a.uid_acquereur
  AND up.is_main = TRUE
  AND a.uid_acquereur IS NOT NULL
  AND a.profile_id_acquereur IS NULL;

CREATE INDEX IF NOT EXISTS idx_animaux_profile_eleveur   ON animaux (profile_id_eleveur);
CREATE INDEX IF NOT EXISTS idx_animaux_profile_acquereur ON animaux (profile_id_acquereur);

-- ─── 8. Colonne profile_id sur animaux_proprietes ───────────

ALTER TABLE animaux_proprietes
  ADD COLUMN IF NOT EXISTS profile_id_proprio UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE animaux_proprietes ap
SET profile_id_proprio = up.id
FROM user_profiles up
WHERE up.uid = ap.uid_proprio
  AND up.is_main = TRUE
  AND ap.profile_id_proprio IS NULL;

CREATE INDEX IF NOT EXISTS idx_animaux_prop_profile ON animaux_proprietes (profile_id_proprio);

-- ─── 9. Colonnes profile_id sur tables agenda / tâches ──────

ALTER TABLE agenda
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE agenda ag
SET profile_id = up.id
FROM user_profiles up
WHERE up.uid = ag.uid
  AND up.is_main = TRUE
  AND ag.profile_id IS NULL;

ALTER TABLE plan_taches
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE plan_taches pt
SET profile_id = up.id
FROM user_profiles up
WHERE up.uid = pt.uid_eleveur
  AND up.is_main = TRUE
  AND pt.profile_id IS NULL;

-- ─── 10. Colonnes profile_id sur contrats / notifications ───

ALTER TABLE contrats
  ADD COLUMN IF NOT EXISTS profile_id_cedant   UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS profile_id_acquereur UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE contrats c
SET profile_id_cedant = up.id
FROM user_profiles up
WHERE up.uid = c.uid_cedant
  AND up.is_main = TRUE
  AND c.profile_id_cedant IS NULL;

UPDATE contrats c
SET profile_id_acquereur = up.id
FROM user_profiles up
WHERE up.uid = c.uid_acquereur
  AND up.is_main = TRUE
  AND c.profile_id_acquereur IS NULL;

ALTER TABLE notifications
  ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

UPDATE notifications n
SET profile_id = up.id
FROM user_profiles up
WHERE up.uid = n.uid
  AND up.is_main = TRUE
  AND n.profile_id IS NULL;

-- ─── VÉRIFICATION FINALE ─────────────────────────────────────

SELECT 'animal_access'   AS table_name, COUNT(*) AS lignes FROM animal_access
UNION ALL
SELECT 'profile_members',                COUNT(*) FROM profile_members
UNION ALL
SELECT 'animaux avec profile_id_eleveur',
  COUNT(*) FROM animaux WHERE profile_id_eleveur IS NOT NULL
UNION ALL
SELECT 'animaux_proprietes avec profile_id_proprio',
  COUNT(*) FROM animaux_proprietes WHERE profile_id_proprio IS NOT NULL;
