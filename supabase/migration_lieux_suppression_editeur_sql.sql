-- ════════════════════════════════════════════════════════════════════════
-- Lieux pet-friendly : complément de migration_lieux_avis_suppression.sql.
--
-- Le garde-fou pf_garde_suppression_fiche laissait passer la clé service
-- (API admin) mais bloquait une suppression lancée à la main dans l'éditeur
-- SQL de Supabase (compte postgres, sans jeton). Ce complément laisse aussi
-- passer les comptes d'administration de la base. Rien d'autre ne change :
-- les utilisateurs de l'appli et du site (rôles anon / authenticated) restent
-- soumis aux mêmes contrôles.
--
-- Aucune donnée n'est lue ni modifiée : seule la fonction est remplacée.
-- Retour arrière : voir la section ROLLBACK en fin de fichier.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

CREATE OR REPLACE FUNCTION public.pf_garde_suppression_fiche()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(auth.jwt() ->> 'role', '') = 'service_role'
     OR current_user IN ('postgres', 'supabase_admin') THEN
    RETURN OLD;
  END IF;
  -- Fiche communautaire : seul son auteur (son brouillon, parcours existant
  -- des particuliers) peut encore la supprimer ; jamais son gestionnaire.
  IF OLD.origine = 'communaute' AND OLD.ajoute_par_uid IS DISTINCT FROM (auth.jwt() ->> 'sub') THEN
    RAISE EXCEPTION 'pf_fiche_communautaire'
      USING HINT = 'Une fiche ajoutée par la communauté ne peut être supprimée que par l''équipe PetsMatch.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.petfriendly_reviews r
              WHERE r.place_id = OLD.id
                AND r.user_uid IS DISTINCT FROM (auth.jwt() ->> 'sub')) THEN
    RAISE EXCEPTION 'pf_fiche_avec_avis'
      USING HINT = 'Une fiche qui porte des avis clients ne peut être supprimée que par l''équipe PetsMatch.';
  END IF;
  RETURN OLD;
END $$;

COMMIT;

-- Vérification (lecture seule) : doit afficher « current_user IN ('postgres', 'supabase_admin') ».
-- select pg_get_functiondef('public.pf_garde_suppression_fiche'::regproc);

-- ════════════════════════════════════════════════════════════════════════
-- ROLLBACK (à exécuter seulement pour revenir à la version précédente) :
-- BEGIN;
-- CREATE OR REPLACE FUNCTION public.pf_garde_suppression_fiche()
-- RETURNS trigger LANGUAGE plpgsql AS $$
-- BEGIN
--   IF coalesce(auth.jwt() ->> 'role', '') = 'service_role' THEN RETURN OLD; END IF;
--   IF OLD.origine = 'communaute' AND OLD.ajoute_par_uid IS DISTINCT FROM (auth.jwt() ->> 'sub') THEN
--     RAISE EXCEPTION 'pf_fiche_communautaire'
--       USING HINT = 'Une fiche ajoutée par la communauté ne peut être supprimée que par l''équipe PetsMatch.';
--   END IF;
--   IF EXISTS (SELECT 1 FROM public.petfriendly_reviews r
--               WHERE r.place_id = OLD.id
--                 AND r.user_uid IS DISTINCT FROM (auth.jwt() ->> 'sub')) THEN
--     RAISE EXCEPTION 'pf_fiche_avec_avis'
--       USING HINT = 'Une fiche qui porte des avis clients ne peut être supprimée que par l''équipe PetsMatch.';
--   END IF;
--   RETURN OLD;
-- END $$;
-- COMMIT;
-- ════════════════════════════════════════════════════════════════════════
