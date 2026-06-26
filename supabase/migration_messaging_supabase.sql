-- Migration messagerie unifiée Supabase
-- Étend les tables conversations + messages existantes

-- Ajouter DEFAULT UUID aux clés primaires TEXT
ALTER TABLE conversations ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE messages      ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;

ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS type TEXT DEFAULT 'direct',
  ADD COLUMN IF NOT EXISTS nom TEXT,
  ADD COLUMN IF NOT EXISTS created_by TEXT,
  ADD COLUMN IF NOT EXISTS participants_info JSONB DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS pro_profile_id UUID,
  ADD COLUMN IF NOT EXISTS consumer_profile_id UUID,
  ADD COLUMN IF NOT EXISTS deleted_for JSONB DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS pinned_for JSONB DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS archived_for JSONB DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS muted_for JSONB DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS categorie TEXT;

-- Table bloquages (remplace collection Firestore 'bloquer')
CREATE TABLE IF NOT EXISTS bloquages (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid         TEXT NOT NULL,
  blocked_uid TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(uid, blocked_uid)
);
CREATE INDEX IF NOT EXISTS idx_bloquages_uid ON bloquages(uid);
ALTER TABLE bloquages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "bloquages_all" ON bloquages;
CREATE POLICY "bloquages_all" ON bloquages USING (true) WITH CHECK (true);

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS msg_type TEXT DEFAULT 'text',
  ADD COLUMN IF NOT EXISTS lat NUMERIC,
  ADD COLUMN IF NOT EXISTS lng NUMERIC,
  ADD COLUMN IF NOT EXISTS sender_profile_id UUID,
  ADD COLUMN IF NOT EXISTS alerte_id TEXT;

-- RLS permissif (Firebase Auth → uid null)
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages      ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "conv_all" ON conversations;
DROP POLICY IF EXISTS "msg_all"  ON messages;

CREATE POLICY "conv_all" ON conversations USING (true) WITH CHECK (true);
CREATE POLICY "msg_all"  ON messages      USING (true) WITH CHECK (true);

-- Index pour les requêtes fréquentes
CREATE INDEX IF NOT EXISTS idx_conv_type        ON conversations(type);
CREATE INDEX IF NOT EXISTS idx_conv_updated     ON conversations(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_msg_conv_created ON messages(conversation_id, created_at);

-- Activer Realtime sur les deux tables
ALTER PUBLICATION supabase_realtime ADD TABLE conversations;
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
