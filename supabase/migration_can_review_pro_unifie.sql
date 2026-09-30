-- ══════════════════════════════════════════════════════════════════════════
-- Avis pro — can_review_pro : une seule version (3 surcharges → 1)
-- ══════════════════════════════════════════════════════════════════════════
-- Trois versions coexistaient : (text,text), (text,text,uuid) et
-- (text,text,uuid,uuid) — les deux dernières avec paramètres par défaut.
-- Conséquences constatées (30/09/2026) :
--   1. L'appli appelle rpc('can_review_pro') avec 3 paramètres quand le
--      profil du pro est inconnu → « could not choose the best candidate
--      function » → affiché comme « pas éligible ».
--   2. La policy avis_pro_insert utilisait la version 3 paramètres, qui
--      ignore les CESSIONS, alors que l'écran (version 4 paramètres) les
--      compte → un acquéreur voyait « laisser un avis » puis son avis était
--      refusé à l'enregistrement.
--   3. Toute recréation de la policy échouait (ambiguïté) — rencontré en
--      recopiant la prod vers le staging.
--
-- Correctif : seule la version 4 paramètres est conservée (RDV + comptes
-- rendus + cessions, scopés par profil client ET profil pro) ; la policy
-- l'appelle explicitement avec les 4 colonnes de l'avis.
-- ══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS avis_pro_insert ON public.avis_pro;

DROP FUNCTION IF EXISTS public.can_review_pro(text, text, uuid);
DROP FUNCTION IF EXISTS public.can_review_pro(text, text);

CREATE POLICY avis_pro_insert ON public.avis_pro
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = client_uid
    AND public.can_review_pro(pro_uid, client_uid, client_profile_id, pro_profile_id)
  );

GRANT EXECUTE ON FUNCTION public.can_review_pro(text, text, uuid, uuid) TO anon, authenticated;

-- Vérification : une seule version, et la policy est en place
SELECT pg_get_function_identity_arguments(oid) AS version_restante FROM pg_proc WHERE proname = 'can_review_pro';
SELECT polname FROM pg_policy WHERE polname = 'avis_pro_insert';

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK : recréer les versions 2 et 3 paramètres (définitions dans
-- migration_rls_fix_avis_pro_profile_mixing*.sql) puis la policy d'origine :
--   ... public.can_review_pro(pro_uid, client_uid, client_profile_id)
-- ══════════════════════════════════════════════════════════════════════════
