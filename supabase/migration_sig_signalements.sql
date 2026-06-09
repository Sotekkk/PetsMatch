-- SIG01-SIG03 : table signalements
-- À exécuter dans l'éditeur SQL Supabase

CREATE TABLE IF NOT EXISTS signalements (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_uid  TEXT NOT NULL,
  target_type   TEXT NOT NULL CHECK (target_type IN ('user', 'annonce', 'profil_pro')),
  target_id     TEXT NOT NULL,
  raison        TEXT NOT NULL CHECK (raison IN ('contenu_inapproprie', 'spam', 'faux_profil', 'maltraitance', 'autre')),
  description   TEXT,
  statut        TEXT NOT NULL DEFAULT 'en_attente' CHECK (statut IN ('en_attente', 'traite', 'rejete')),
  admin_note    TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  handled_at    TIMESTAMPTZ,
  handled_by    TEXT
);

-- Un utilisateur ne peut signaler la même ressource qu'une seule fois
CREATE UNIQUE INDEX IF NOT EXISTS idx_sig_unique
  ON signalements (reporter_uid, target_type, target_id);

-- Index pour requêtes admin (filtre par statut, par cible)
CREATE INDEX IF NOT EXISTS idx_sig_statut ON signalements (statut);
CREATE INDEX IF NOT EXISTS idx_sig_target ON signalements (target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_sig_reporter ON signalements (reporter_uid);

-- SIG03 : vue pour les ressources dépassant le seuil de 3 signalements non traités
-- Utilisée par le panel admin (SIG04) pour afficher les badges d'alerte
CREATE OR REPLACE VIEW signalements_alertes AS
  SELECT
    target_type,
    target_id,
    COUNT(*) AS nb_signalements,
    MIN(created_at) AS premier_signalement,
    MAX(created_at) AS dernier_signalement
  FROM signalements
  WHERE statut = 'en_attente'
  GROUP BY target_type, target_id
  HAVING COUNT(*) >= 3
  ORDER BY nb_signalements DESC;
