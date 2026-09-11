-- ═══════════════════════════════════════════════════════════════════════════
-- Balades ludiques — colonnes *_profile_id manquantes sur TOUTES les tables
--
-- Diagnostic en base (service_role, colonne par colonne) : la migration
-- migration_balades_ludiques.sql utilise `CREATE TABLE IF NOT EXISTS`, qui
-- ne modifie PAS une table déjà existante — les tables balades_ludiques*
-- existaient déjà (créées par une version antérieure de la migration, sans
-- le scoping par profil) au moment où les colonnes *_profile_id ont été
-- ajoutées au fichier. Résultat : AUCUNE des colonnes *_profile_id
-- n'existe réellement en base, sur AUCUNE des tables du module — toute
-- création de balade / progression / avis / favori échoue avec
-- PostgrestException PGRST204 "column ... does not exist".
--
-- Vérifié : les 8 tables du module sont vides (0 ligne) en prod — ce
-- correctif ADD COLUMN ... NOT NULL est donc sans risque de backfill.
--
-- Volontairement minimal (juste les colonnes + index, pas de contraintes
-- UNIQUE/PRIMARY KEY) pour ne pas entrer en conflit avec des contraintes
-- déjà posées sous un autre nom lors de la création initiale des tables.
--
-- À exécuter dans Supabase SQL Editor (une seule fois).
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.balades_ludiques
  ADD COLUMN IF NOT EXISTS createur_profile_id uuid REFERENCES public.user_profiles(id) ON DELETE SET NULL;

ALTER TABLE public.balades_ludiques_progressions
  ADD COLUMN IF NOT EXISTS joueur_profile_id uuid REFERENCES public.user_profiles(id) ON DELETE CASCADE;
ALTER TABLE public.balades_ludiques_progressions
  ALTER COLUMN joueur_profile_id SET NOT NULL;

ALTER TABLE public.balades_ludiques_validations
  ADD COLUMN IF NOT EXISTS joueur_profile_id uuid REFERENCES public.user_profiles(id) ON DELETE SET NULL;

ALTER TABLE public.balades_ludiques_avis
  ADD COLUMN IF NOT EXISTS profile_id uuid REFERENCES public.user_profiles(id) ON DELETE CASCADE;
ALTER TABLE public.balades_ludiques_avis
  ALTER COLUMN profile_id SET NOT NULL;

ALTER TABLE public.balades_ludiques_favoris
  ADD COLUMN IF NOT EXISTS profile_id uuid REFERENCES public.user_profiles(id) ON DELETE CASCADE;
ALTER TABLE public.balades_ludiques_favoris
  ALTER COLUMN profile_id SET NOT NULL;

ALTER TABLE public.badges_obtenus
  ADD COLUMN IF NOT EXISTS profile_id uuid REFERENCES public.user_profiles(id) ON DELETE CASCADE;
ALTER TABLE public.badges_obtenus
  ALTER COLUMN profile_id SET NOT NULL;

ALTER TABLE public.joueurs_xp
  ADD COLUMN IF NOT EXISTS profile_id uuid REFERENCES public.user_profiles(id) ON DELETE CASCADE;

-- Index utiles (repris de migration_balades_ludiques.sql, idempotents).
CREATE INDEX IF NOT EXISTS idx_bl_createur_profile ON public.balades_ludiques (createur_profile_id);
CREATE INDEX IF NOT EXISTS idx_blpr_joueur_profile ON public.balades_ludiques_progressions (joueur_profile_id);
CREATE INDEX IF NOT EXISTS idx_bla_profile ON public.balades_ludiques_avis (profile_id);
CREATE INDEX IF NOT EXISTS idx_bo_profile ON public.badges_obtenus (profile_id);
