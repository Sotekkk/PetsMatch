-- ============================================================
-- PetsMatch V2 — Patch 11 : sender_profile_id sur notifications
-- ============================================================

ALTER TABLE notifications ADD COLUMN IF NOT EXISTS sender_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS recipient_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_notif_sender_profile   ON notifications(sender_profile_id);
CREATE INDEX IF NOT EXISTS idx_notif_recipient_profile ON notifications(recipient_profile_id);

-- Backfill sender_profile_id depuis from_uid dans data (pour les likes existants)
UPDATE notifications n
SET sender_profile_id = (
  SELECT up.id FROM user_profiles up
  WHERE up.uid = (n.data->>'fromUid')
  ORDER BY up.is_main DESC, up.created_at ASC
  LIMIT 1
)
WHERE n.type = 'like'
  AND n.data->>'fromUid' IS NOT NULL
  AND n.sender_profile_id IS NULL;
