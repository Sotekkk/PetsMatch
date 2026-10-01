-- ════════════════════════════════════════════════════════════════════════
-- Revue 5d : tables publiques par nature — corrections.
--
-- 1. tests_genetiques : résultats génétiques de TOUS les animaux lisibles
--    par tous → visibles par le propriétaire / les personnes liées
--    (is_animal_owner_or_related), pour un reproducteur public, pour un
--    animal d'une annonce (vendu, étalon, mère, père), et l'admin.
-- 2. balades_ludiques_validations : position GPS + photo de chaque joueur
--    à chaque étape lisibles par tous → le joueur et le créateur.
-- 3. balades_ludiques_points : réponses des énigmes (question_reponse,
--    qr_code_value) lisibles par tous, comparées sur le téléphone (triche)
--    → vue balades_ludiques_points_complet (réponses visibles du seul
--    créateur / admin), vérification côté serveur pm_verifier_defi, plus
--    de lecture directe de ces deux colonnes.
-- 4. app_config : mot de passe bêta lisible par l'API → ligne masquée,
--    vérification côté serveur pm_verifier_code_beta.
-- Restent publics (par nature) : annonces, lieux, avis, forum, événements,
-- groupes, tarifs / offres des pros, catalogues, badges, classement,
-- stories, alertes perdus / trouvés (contact voulu), etc.
-- À surveiller : creneaux_pro.lieu_adresse / lieu_lat / lieu_lng /
-- trajet_origine — vides aujourd'hui, mais lisibles si remplis.
--
-- ⚠ Points 3 et 4 : l'appli et le site doivent utiliser la vue et les RPC
--   (même commit) ; une ancienne version de l'appli ne pourra plus jouer
--   les défis « question » / « QR code » (lecture refusée).
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. tests_genetiques ────────────────────────────────────────────────
DROP POLICY IF EXISTS tests_genetiques_select ON public.tests_genetiques;
CREATE POLICY tests_genetiques_select ON public.tests_genetiques
  FOR SELECT TO anon, authenticated
  USING (
    public.is_animal_owner_or_related(animal_id, auth.jwt() ->> 'sub')
    OR EXISTS (SELECT 1 FROM public.animaux a
               WHERE a.id = tests_genetiques.animal_id AND a.reproducteur_public)
    OR EXISTS (SELECT 1 FROM public.annonces an
               WHERE tests_genetiques.animal_id IN (an.animal_id, an.etalon_animal_id,
                                                     an.mere_animal_id, an.pere_animal_id))
    OR public.is_admin_uid(auth.jwt() ->> 'sub')
  );

-- ── 2. balades_ludiques_validations ────────────────────────────────────
DROP POLICY IF EXISTS blv_select ON public.balades_ludiques_validations;
CREATE POLICY blv_select ON public.balades_ludiques_validations
  FOR SELECT TO anon, authenticated
  USING (
    (auth.jwt() ->> 'sub') = joueur_uid
    OR EXISTS (SELECT 1 FROM public.balades_ludiques_points pt
               JOIN public.balades_ludiques b ON b.id = pt.balade_id
               WHERE pt.id = balades_ludiques_validations.point_id
                 AND b.createur_uid = (auth.jwt() ->> 'sub'))
  );

-- ── 3. balades_ludiques_points : réponses masquées ─────────────────────
CREATE OR REPLACE VIEW public.balades_ludiques_points_complet WITH (security_barrier) AS
  SELECT pt.id, pt.balade_id, pt.ordre, pt.titre, pt.description, pt.lat, pt.lng,
         pt.rayon_validation_m, pt.type_defi, pt.question_texte,
         CASE WHEN v.createur THEN pt.question_reponse END AS question_reponse,
         pt.consigne_texte,
         CASE WHEN v.createur THEN pt.qr_code_value END AS qr_code_value,
         pt.indice, pt.photo_illustration_url, pt.created_at
  FROM public.balades_ludiques_points pt
  JOIN public.balades_ludiques b ON b.id = pt.balade_id
  CROSS JOIN LATERAL (SELECT (b.createur_uid = (auth.jwt() ->> 'sub')
                              OR (SELECT public.is_admin_uid(auth.jwt() ->> 'sub'))) AS createur) v;
GRANT SELECT ON public.balades_ludiques_points_complet TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.pm_verifier_defi(p_point_id uuid, p_reponse text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE pt.type_defi
           WHEN 'question' THEN lower(trim(coalesce(p_reponse, ''))) = lower(trim(coalesce(pt.question_reponse, '')))
                                AND trim(coalesce(pt.question_reponse, '')) <> ''
           WHEN 'qr_code'  THEN trim(coalesce(p_reponse, '')) = trim(coalesce(pt.qr_code_value, ''))
                                AND trim(coalesce(pt.qr_code_value, '')) <> ''
           ELSE true
         END
  FROM balades_ludiques_points pt WHERE pt.id = p_point_id;
$$;
GRANT EXECUTE ON FUNCTION public.pm_verifier_defi(uuid, text) TO anon, authenticated;

REVOKE SELECT ON public.balades_ludiques_points FROM anon, authenticated;
GRANT SELECT (id, balade_id, ordre, titre, description, lat, lng, rayon_validation_m, type_defi,
              question_texte, consigne_texte, indice, photo_illustration_url, created_at)
  ON public.balades_ludiques_points TO anon, authenticated;

-- ── 4. app_config : mot de passe bêta ──────────────────────────────────
DROP POLICY IF EXISTS app_config_read ON public.app_config;
CREATE POLICY app_config_read ON public.app_config
  FOR SELECT TO anon, authenticated
  USING (key <> 'beta_password');

CREATE OR REPLACE FUNCTION public.pm_verifier_code_beta(p_code text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce((SELECT trim(value) = trim(coalesce(p_code, '')) AND trim(value) <> ''
                   FROM app_config WHERE key = 'beta_password'), false);
$$;
GRANT EXECUTE ON FUNCTION public.pm_verifier_code_beta(text) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
