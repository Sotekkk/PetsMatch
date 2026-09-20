-- Marqueur "notifications Pets Social vues" (bulle rouge du cœur) — jusqu'ici
-- stocké uniquement en local (SharedPreferences), donc perdu à chaque
-- réinstallation de l'app (la bulle réapparaît avec tout l'historique).
-- Déplacé en base, sur le profil, pour être durable comme le reste.
alter table user_profiles
  add column if not exists social_notif_seen_at timestamptz;
