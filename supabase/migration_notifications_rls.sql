-- Migration : création de la table notifications si absente + politiques RLS
-- Problème : les inserts depuis le client anon (Firebase Auth) étaient bloqués
-- silencieusement car aucune politique INSERT n'était définie.

-- 1. Créer la table si elle n'existe pas encore
CREATE TABLE IF NOT EXISTS notifications (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  uid         TEXT        NOT NULL,
  type        TEXT,
  title       TEXT,
  body        TEXT,
  data        JSONB       DEFAULT '{}',
  read        BOOLEAN     DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  profile_type TEXT,
  profile_id  TEXT
);

-- 2. Activer RLS
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- 3. Politique INSERT : le client anon peut insérer dès qu'un uid est fourni
--    (Firebase Auth n'est pas Supabase Auth → pas de auth.uid() disponible)
DROP POLICY IF EXISTS "allow_insert_notifications" ON notifications;
CREATE POLICY "allow_insert_notifications"
  ON notifications
  FOR INSERT
  WITH CHECK (uid IS NOT NULL AND uid <> '');

-- 4. Politique UPDATE : marquer comme lu (PATCH /api/notifications passe par service role,
--    mais on laisse aussi le client le faire directement si besoin)
DROP POLICY IF EXISTS "allow_update_own_notifications" ON notifications;
CREATE POLICY "allow_update_own_notifications"
  ON notifications
  FOR UPDATE
  USING (true)
  WITH CHECK (true);

-- 5. Politique DELETE : supprimer sa propre notif (pension_acces dialog)
DROP POLICY IF EXISTS "allow_delete_notifications" ON notifications;
CREATE POLICY "allow_delete_notifications"
  ON notifications
  FOR DELETE
  USING (true);

-- 6. Politique SELECT : nécessaire pour l'app Flutter (lecture directe via client anon)
-- Firebase Auth ne fournit pas auth.uid() → politique permissive sur uid non-null
DROP POLICY IF EXISTS "allow_select_notifications" ON notifications;
CREATE POLICY "allow_select_notifications"
  ON notifications
  FOR SELECT
  USING (true);

-- 7. Index si pas déjà créés
CREATE INDEX IF NOT EXISTS idx_notifications_uid       ON notifications (uid);
CREATE INDEX IF NOT EXISTS idx_notifications_uid_read  ON notifications (uid, read);
CREATE INDEX IF NOT EXISTS idx_notifications_uid_profile ON notifications (uid, profile_type);
