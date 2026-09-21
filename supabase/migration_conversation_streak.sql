-- Flamme de discussion (façon Snapchat) : compteur de jours consécutifs où
-- LES DEUX participants d'une conversation 1:1 se sont écrit. Concept
-- indépendant de la flamme d'engagement (user_profiles.streak_count,
-- cf. migration_gamification_phase1.sql) — celle-ci est par conversation,
-- pas par utilisateur, et ne s'applique pas aux groupes.
-- Comme le reste du projet, pas de RLS restrictive (Firebase Auth + client
-- anon Supabase, auth.uid() inexploitable) : filtrage applicatif.

ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS msg_streak_count        INTEGER NOT NULL DEFAULT 0 CHECK (msg_streak_count >= 0),
  ADD COLUMN IF NOT EXISTS msg_streak_last_date     DATE,
  ADD COLUMN IF NOT EXISTS msg_streak_today_date    DATE,
  ADD COLUMN IF NOT EXISTS msg_streak_today_senders JSONB DEFAULT '[]';
