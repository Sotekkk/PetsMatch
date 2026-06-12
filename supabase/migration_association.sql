-- ============================================================
-- PetsMatch — Migration : Profil Association
-- ============================================================

-- Colonnes ajoutées à la table users
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS is_association          BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS rna                     TEXT,
  ADD COLUMN IF NOT EXISTS agrement_prefectoral    TEXT,
  ADD COLUMN IF NOT EXISTS capacite_accueil        INTEGER,
  ADD COLUMN IF NOT EXISTS site_web_asso           TEXT,
  ADD COLUMN IF NOT EXISTS especes_accueillies     JSONB DEFAULT '[]';

-- Index pour les requêtes associations
CREATE INDEX IF NOT EXISTS idx_users_is_association ON users(is_association);

-- Table familles_accueil
CREATE TABLE IF NOT EXISTS familles_accueil (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  association_uid   TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  fa_uid            TEXT REFERENCES users(uid) ON DELETE SET NULL,
  prenom            TEXT NOT NULL,
  nom               TEXT NOT NULL,
  email             TEXT,
  telephone         TEXT,
  adresse           TEXT,
  ville             TEXT,
  code_postal       TEXT,
  especes_accueil   JSONB DEFAULT '[]',
  capacite_max      INTEGER DEFAULT 1,
  actif             BOOLEAN DEFAULT TRUE,
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

-- Animaux en FA : lien animal → famille d'accueil
ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS fa_id        UUID REFERENCES familles_accueil(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS date_entree  DATE,
  ADD COLUMN IF NOT EXISTS date_sortie  DATE,
  ADD COLUMN IF NOT EXISTS motif_sortie TEXT;

-- Statuts étendus pour les animaux d'association
-- Les valeurs possibles pour statut dans animaux :
-- Éleveur    : present | sorti | decede
-- Association: en_soin | disponible | adopte | en_fa | decede | transfere

-- Table bénévoles (réutilise la structure employes)
-- Un bénévole a type = 'benevole' dans la table employes
-- Aucun changement nécessaire si is_benevole est géré par type

-- Index FA
CREATE INDEX IF NOT EXISTS idx_fa_association ON familles_accueil(association_uid);
CREATE INDEX IF NOT EXISTS idx_animaux_fa     ON animaux(fa_id);
