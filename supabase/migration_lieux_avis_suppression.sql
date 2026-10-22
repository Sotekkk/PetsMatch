-- ════════════════════════════════════════════════════════════════════════
-- Lieux pet-friendly : les avis clients ne peuvent être supprimés que par
-- leur auteur ou par l'équipe PetsMatch (clé service / API admin).
--
-- Avant : la policy petfriendly_reviews_delete autorisait aussi le
-- gestionnaire de l'établissement (et ses cogérants) à supprimer n'importe
-- quel avis de sa fiche, y compris par accès direct à la base. Et supprimer
-- la fiche elle-même effaçait ses avis.
--
-- Après :
--   • avis : suppression par l'auteur uniquement (la modération — masquer,
--     refuser — reste à l'API admin, clé service) ;
--   • réponse de l'établissement : inchangée (policy UPDATE + garde-fou
--     pf_avis_garde de migration_lieux_avis_criteres.sql : le gestionnaire ne
--     peut modifier que reponse_pro) ;
--   • signalement / contestation : inchangés (table signalements) ;
--   • fiche : un gestionnaire ne peut plus supprimer une fiche qui porte des
--     avis d'autres membres, ni une fiche ajoutée par la communauté
--     (revendiquée) — décision réservée à l'équipe PetsMatch. Le particulier
--     garde la suppression de son propre brouillon (policy pf_delete).
--
-- À lancer après migration_rls_tighten_perdus_petfriendly.sql,
-- migration_lieux_communautaires.sql et migration_lieux_avis_criteres.sql.
-- Retour arrière : voir la section ROLLBACK en fin de fichier.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

-- ── 1. Avis : suppression par l'auteur seulement ────────────────────────
DROP POLICY IF EXISTS "petfriendly_reviews_delete" ON public.petfriendly_reviews;
CREATE POLICY "petfriendly_reviews_delete" ON public.petfriendly_reviews
  FOR DELETE USING ((auth.jwt() ->> 'sub') = user_uid);

-- ── 2. Fiche : pas de suppression qui emporterait des avis clients ───────
CREATE OR REPLACE FUNCTION public.pf_garde_suppression_fiche()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(auth.jwt() ->> 'role', '') = 'service_role' THEN RETURN OLD; END IF;
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

DROP TRIGGER IF EXISTS trg_pf_garde_suppression_fiche ON public.petfriendly_places;
CREATE TRIGGER trg_pf_garde_suppression_fiche
  BEFORE DELETE ON public.petfriendly_places
  FOR EACH ROW EXECUTE FUNCTION public.pf_garde_suppression_fiche();

COMMIT;

-- ════════════════════════════════════════════════════════════════════════
-- ROLLBACK (à exécuter seulement pour revenir en arrière) :
-- BEGIN;
-- DROP TRIGGER IF EXISTS trg_pf_garde_suppression_fiche ON public.petfriendly_places;
-- DROP FUNCTION IF EXISTS public.pf_garde_suppression_fiche();
-- DROP POLICY IF EXISTS "petfriendly_reviews_delete" ON public.petfriendly_reviews;
-- CREATE POLICY "petfriendly_reviews_delete" ON public.petfriendly_reviews
--   FOR DELETE USING (
--     (auth.jwt() ->> 'sub') = user_uid
--     OR EXISTS (
--       SELECT 1 FROM public.petfriendly_places p
--       WHERE p.id = petfriendly_reviews.place_id
--         AND (p.uid_pro = (auth.jwt() ->> 'sub')
--           OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = p.uid_pro AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL))
--     )
--   );
-- COMMIT;
-- ════════════════════════════════════════════════════════════════════════
