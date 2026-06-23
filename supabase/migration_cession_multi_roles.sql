-- Cession multi-rôles : types de cédant/acquéreur pour toutes les combinaisons
-- Pris en charge : éleveur/particulier, éleveur/association, association/particulier,
--                  particulier/association (abandon), association/éleveur

-- Colonnes informatives pour tracer les rôles (uid_eleveur = uid cédant dans tous les cas)
ALTER TABLE cessions ADD COLUMN IF NOT EXISTS type_cedant   TEXT; -- 'eleveur' | 'particulier' | 'association'
ALTER TABLE cessions ADD COLUMN IF NOT EXISTS type_acquereur TEXT; -- 'eleveur' | 'particulier' | 'association'

-- Index pour requêtes par type
CREATE INDEX IF NOT EXISTS idx_cessions_type_cedant    ON cessions(type_cedant);
CREATE INDEX IF NOT EXISTS idx_cessions_type_acquereur ON cessions(type_acquereur);

-- Autoriser uid_acquereur à mettre à jour les animaux qu'il a reçus
-- (nécessaire pour la re-cession par un particulier ou une association)
-- RLS animaux : la politique existante utilise USING(true), donc pas de blocage supplémentaire.
-- Cette migration est documentaire — s'assurer que la politique SELECT et UPDATE restent ouvertes.
