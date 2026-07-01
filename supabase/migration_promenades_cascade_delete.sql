-- ============================================================
-- Migration : Suppression en cascade pour les promenades
-- Date      : 2026-07-01
-- ============================================================

-- ── 1. promenades_participants → ON DELETE CASCADE ───────────────────────────

ALTER TABLE promenades_participants
  DROP CONSTRAINT IF EXISTS promenades_participants_promenade_id_fkey;

ALTER TABLE promenades_participants
  ADD CONSTRAINT promenades_participants_promenade_id_fkey
    FOREIGN KEY (promenade_id)
    REFERENCES promenades(id)
    ON DELETE CASCADE;

-- ── 2. promenades_messages → ON DELETE CASCADE ──────────────────────────────

ALTER TABLE promenades_messages
  DROP CONSTRAINT IF EXISTS promenades_messages_promenade_id_fkey;

ALTER TABLE promenades_messages
  ADD CONSTRAINT promenades_messages_promenade_id_fkey
    FOREIGN KEY (promenade_id)
    REFERENCES promenades(id)
    ON DELETE CASCADE;

-- ── 3. Trigger : supprimer les notifications liées à la promenade ─────────

CREATE OR REPLACE FUNCTION delete_promenade_notifications()
RETURNS TRIGGER AS $$
BEGIN
  DELETE FROM notifications
  WHERE type IN ('promenade_invite', 'promenade_message', 'promenade_update')
    AND (data->>'promenade_id' = OLD.id::text OR data->>'promenadeId' = OLD.id::text);
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_delete_promenade_notifications ON promenades;
CREATE TRIGGER trg_delete_promenade_notifications
  BEFORE DELETE ON promenades
  FOR EACH ROW EXECUTE FUNCTION delete_promenade_notifications();

-- ── 4. Ajouter pro_profile_id dans documents_animaux ────────────────────────

ALTER TABLE documents_animaux
  ADD COLUMN IF NOT EXISTS pro_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

-- ── 5. Vérification des contraintes créées ──────────────────────────────────
SELECT
  tc.table_name,
  tc.constraint_name,
  rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.referential_constraints rc
  ON tc.constraint_name = rc.constraint_name
WHERE tc.table_name IN ('promenades_participants', 'promenades_messages')
  AND tc.constraint_type = 'FOREIGN KEY';
