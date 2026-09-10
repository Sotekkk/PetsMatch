-- ═══════════════════════════════════════════════════════════════════════════
-- Pets Social — pseudo au choix (au lieu du vrai nom)
-- ───────────────────────────────────────────────────────────────────────────
-- Champ optionnel sur user_profiles. S'il est renseigné, c'est lui qui
-- s'affiche dans Pets Social (posts, commentaires, listes, profil) à la place
-- de « prénom nom ». Vide = vrai nom affiché comme avant.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS social_pseudo TEXT;
