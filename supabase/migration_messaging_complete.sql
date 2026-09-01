-- ============================================================================
-- Messagerie web — migration COMPLÈTE et idempotente
-- Regroupe : migration_messaging_supabase.sql + réactions emoji + thèmes de
-- conversation + signalement de conversation (commit "aligne le chat web avec
-- l'app Flutter"), qui n'avaient jamais été livrés en fichier.
--
-- À exécuter dans Supabase → SQL Editor (rejouable sans risque).
-- Si « Failed to fetch (auth.supabase.io) » : réessayer (erreur transitoire du
-- dashboard), ou coller ce script par blocs.
-- ============================================================================

-- ── conversations : colonnes ────────────────────────────────────────────────
ALTER TABLE conversations ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS type                TEXT DEFAULT 'direct',
  ADD COLUMN IF NOT EXISTS nom                 TEXT,
  ADD COLUMN IF NOT EXISTS created_by          TEXT,
  ADD COLUMN IF NOT EXISTS participants_info   JSONB DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS pro_profile_id      UUID,
  ADD COLUMN IF NOT EXISTS consumer_profile_id UUID,
  ADD COLUMN IF NOT EXISTS deleted_for         JSONB DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS pinned_for          JSONB DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS archived_for        JSONB DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS muted_for           JSONB DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS categorie           TEXT,
  ADD COLUMN IF NOT EXISTS theme_id            TEXT;

-- ── messages : colonnes ─────────────────────────────────────────────────────
ALTER TABLE messages ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS msg_type          TEXT DEFAULT 'text',
  ADD COLUMN IF NOT EXISTS lat               NUMERIC,
  ADD COLUMN IF NOT EXISTS lng               NUMERIC,
  ADD COLUMN IF NOT EXISTS sender_profile_id UUID,
  ADD COLUMN IF NOT EXISTS alerte_id         TEXT;

-- ── bloquages ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bloquages (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid         TEXT NOT NULL,
  blocked_uid TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (uid, blocked_uid)
);
CREATE INDEX IF NOT EXISTS idx_bloquages_uid ON bloquages(uid);
ALTER TABLE bloquages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "bloquages_all" ON bloquages;
CREATE POLICY "bloquages_all" ON bloquages USING (true) WITH CHECK (true);

-- ── message_reactions (réactions emoji) ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS message_reactions (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  uid        TEXT NOT NULL,
  emoji      TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (message_id, uid)
);
CREATE INDEX IF NOT EXISTS idx_message_reactions_msg ON message_reactions(message_id);
ALTER TABLE message_reactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "message_reactions_all" ON message_reactions;
CREATE POLICY "message_reactions_all" ON message_reactions USING (true) WITH CHECK (true);

-- ── conversation_reports (signalement d'une conversation) ───────────────────
CREATE TABLE IF NOT EXISTS conversation_reports (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id TEXT NOT NULL,
  reported_by_uid TEXT NOT NULL,
  reason          TEXT NOT NULL,
  details         TEXT,
  status          TEXT NOT NULL DEFAULT 'pending', -- pending / reviewed / dismissed
  created_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_conversation_reports_status ON conversation_reports(status);
ALTER TABLE conversation_reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "conversation_reports_all" ON conversation_reports;
CREATE POLICY "conversation_reports_all" ON conversation_reports USING (true) WITH CHECK (true);

-- ── RLS permissif sur conversations / messages (Firebase Auth → uid null) ────
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages      ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "conv_all" ON conversations;
DROP POLICY IF EXISTS "msg_all"  ON messages;
CREATE POLICY "conv_all" ON conversations USING (true) WITH CHECK (true);
CREATE POLICY "msg_all"  ON messages      USING (true) WITH CHECK (true);

-- ── Index ───────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_conv_type        ON conversations(type);
CREATE INDEX IF NOT EXISTS idx_conv_updated     ON conversations(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_msg_conv_created ON messages(conversation_id, created_at);

-- ── Realtime (ignore si les tables sont déjà dans la publication) ───────────
DO $$
BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE conversations;      EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE messages;           EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE message_reactions;  EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;
