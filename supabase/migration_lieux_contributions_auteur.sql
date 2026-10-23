-- ════════════════════════════════════════════════════════════════════════
-- Contributions aux lieux : même règle pour les lieux naturels et les lieux
-- pet-friendly (décision 23/10/2026, alignée sur Natacha) — l'auteur modifie
-- et supprime son lieu TANT QU'IL N'EST PAS PUBLIÉ ; une fois publié, il
-- propose une correction / une photo / un équipement, et la suppression
-- revient à l'équipe PetsMatch (API admin, clé service).
--
-- Lieux naturels (avant : l'auteur pouvait tout modifier à tout moment, y
-- compris passer lui-même son lieu en « valide » sans modération ; seul
-- l'admin supprimait) :
--   • modification par l'auteur : seulement hors statut « valide », et toute
--     modification renvoie le lieu « en_attente » (jamais d'auto-publication) ;
--   • lieu publié : l'auteur n'a plus que les colonnes libres de tous
--     (alerte cyano, difficulté, note) — garde-fou pm_natural_places_garde ;
--   • suppression par l'auteur hors statut « valide » ;
--   • photo / équipement proposés : retirables par leur auteur tant qu'ils
--     sont « en_attente ».
-- Lieux pet-friendly : l'auteur supprime sa fiche brouillon, à compléter,
-- en attente ou refusée (avant : brouillon seulement) ; le garde-fou
-- pf_garde_suppression_fiche (avis d'autres membres) reste en place.
--
-- À lancer après migration_rls_tighten_natural_places.sql,
-- migration_natural_places_garde.sql et migration_lieux_communautaires.sql.
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

-- ── Lieux naturels : policies ───────────────────────────────────────────
DROP POLICY IF EXISTS "natural_places_update" ON public.natural_places;
CREATE POLICY "natural_places_update" ON public.natural_places
  FOR UPDATE USING (
    ((auth.jwt() ->> 'sub') = submitted_by_uid AND statut <> 'valide')
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
    OR (statut = 'valide' AND (auth.jwt() ->> 'sub') IS NOT NULL)
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = submitted_by_uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
    OR (statut = 'valide' AND (auth.jwt() ->> 'sub') IS NOT NULL)
  );

DROP POLICY IF EXISTS "natural_places_delete" ON public.natural_places;
CREATE POLICY "natural_places_delete" ON public.natural_places
  FOR DELETE USING (
    public.is_admin_uid((auth.jwt() ->> 'sub'))
    OR ((auth.jwt() ->> 'sub') = submitted_by_uid AND statut <> 'valide')
  );

DROP POLICY IF EXISTS "natural_place_photo_suggestions_delete" ON public.natural_place_photo_suggestions;
CREATE POLICY "natural_place_photo_suggestions_delete" ON public.natural_place_photo_suggestions
  FOR DELETE USING ((auth.jwt() ->> 'sub') = submitted_by_uid AND statut = 'en_attente');

DROP POLICY IF EXISTS "natural_place_amenity_suggestions_delete" ON public.natural_place_amenity_suggestions;
CREATE POLICY "natural_place_amenity_suggestions_delete" ON public.natural_place_amenity_suggestions
  FOR DELETE USING ((auth.jwt() ->> 'sub') = submitted_by_uid AND statut = 'en_attente');

-- ── Lieux naturels : garde-fou des modifications ────────────────────────
CREATE OR REPLACE FUNCTION public.pm_natural_places_garde()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_sub text := auth.jwt() ->> 'sub';
  v_libres text[] := ARRAY['alerte_cyano', 'alerte_cyano_date', 'alerte_cyano_profile_id',
                           'alerte_cyano_lat', 'alerte_cyano_lng', 'alerte_cyano_statut',
                           'alerte_cyano_photo_url', 'niveau_difficulte', 'nb_avis',
                           'note_moyenne', 'updated_at'];
BEGIN
  -- Appels service / éditeur SQL (sans jeton) et administrateurs : libres.
  IF v_sub IS NULL OR is_admin_uid(v_sub) THEN
    RETURN NEW;
  END IF;
  -- Auteur d'un lieu non publié : tout, sauf se publier ou changer d'auteur ;
  -- la modification repasse par la modération.
  IF v_sub = OLD.submitted_by_uid AND OLD.statut <> 'valide' THEN
    NEW.submitted_by_uid := OLD.submitted_by_uid;
    NEW.statut := 'en_attente';
    RETURN NEW;
  END IF;
  -- Lieu publié (auteur compris) : seules les colonnes communautaires.
  IF (to_jsonb(NEW) - v_libres) IS DISTINCT FROM (to_jsonb(OLD) - v_libres) THEN
    RAISE EXCEPTION 'Un lieu publié ne peut être modifié que par l''équipe PetsMatch'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_natural_places_garde ON public.natural_places;
CREATE TRIGGER trg_natural_places_garde
  BEFORE UPDATE ON public.natural_places
  FOR EACH ROW EXECUTE FUNCTION public.pm_natural_places_garde();

-- ── Lieux pet-friendly : suppression par l'auteur tant que non publiée ──
DROP POLICY IF EXISTS pf_delete ON public.petfriendly_places;
CREATE POLICY pf_delete ON public.petfriendly_places FOR DELETE USING (
  uid_pro = (auth.jwt() ->> 'sub')
  OR (uid_pro IS NULL AND ajoute_par_uid = (auth.jwt() ->> 'sub')
      AND statut IN ('brouillon', 'a_corriger', 'en_attente_validation', 'refuse'))
);

COMMIT;
