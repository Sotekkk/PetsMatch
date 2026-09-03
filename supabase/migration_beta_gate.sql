-- Accès privé pendant la phase de test — mot de passe partagé de l'application
-- ============================================================================
-- Table clé/valeur générique de configuration applicative. La ligne
-- `beta_password` est lue par l'app (lib/pages/beta_gate.dart) au lancement ;
-- la modifier ici change le mot de passe sans republier l'app.

CREATE TABLE IF NOT EXISTS app_config (
  key        TEXT PRIMARY KEY,
  value      TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;

-- Lecture publique (l'app utilise la clé anon). Aucune policy d'écriture :
-- modification réservée au dashboard / service_role.
DROP POLICY IF EXISTS app_config_read ON app_config;
CREATE POLICY app_config_read ON app_config FOR SELECT USING (true);
REVOKE INSERT, UPDATE, DELETE ON app_config FROM anon, authenticated;

-- Mot de passe d'accès bêta (à changer avant l'ouverture des tests).
INSERT INTO app_config (key, value)
VALUES ('beta_password', 'petsmatch-beta-2026')
ON CONFLICT (key) DO NOTHING;
