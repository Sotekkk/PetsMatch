-- ============================================================
-- Migration : Commentaires promenades + intégration agenda
-- Date      : 2026-06-30
-- Tickets   : PRO20, PRO21, PRO22
-- ============================================================

-- ── Table commentaires promenades ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS promenades_messages (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  promenade_id    UUID NOT NULL REFERENCES promenades(id) ON DELETE CASCADE,
  user_uid        TEXT NOT NULL,
  user_profile_id UUID REFERENCES user_profiles(id),
  message         TEXT NOT NULL CHECK (char_length(message) <= 1000),
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_prom_msg_promenade ON promenades_messages (promenade_id, created_at);
CREATE INDEX IF NOT EXISTS idx_prom_msg_user      ON promenades_messages (user_uid);

ALTER TABLE promenades_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "prom_msg_select" ON promenades_messages;
CREATE POLICY "prom_msg_select" ON promenades_messages FOR SELECT USING (true);

DROP POLICY IF EXISTS "prom_msg_insert" ON promenades_messages;
CREATE POLICY "prom_msg_insert" ON promenades_messages
  FOR INSERT WITH CHECK (user_uid IS NOT NULL);

DROP POLICY IF EXISTS "prom_msg_delete" ON promenades_messages;
CREATE POLICY "prom_msg_delete" ON promenades_messages
  FOR DELETE USING (true);

-- ── Colonne promenade_id dans agenda_events ───────────────────────────────────
-- Permet de retrouver et supprimer l'événement agenda quand l'user se désinscrit.

ALTER TABLE agenda_events
  ADD COLUMN IF NOT EXISTS promenade_id UUID REFERENCES promenades(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_agenda_promenade ON agenda_events (promenade_id)
  WHERE promenade_id IS NOT NULL;
