-- ══════════════════════════════════════════════════════════════════════════
-- Correctif : mix de profil sur l'éligibilité à laisser un avis pro
-- ══════════════════════════════════════════════════════════════════════════
-- Confirmé en conditions réelles : can_review_pro() ne vérifiait que le
-- compte (uid), pas le PROFIL précis — un rendez-vous pris avec un profil
-- éleveur (ou tout autre profil du même compte) suffisait à rendre éligible
-- le profil PARTICULIER du même compte pour laisser un avis, alors que ce
-- dernier n'a jamais eu affaire au pro. Même famille de bug que les fuites
-- multi-profil déjà corrigées ailleurs dans le projet (animaux, employé,
-- fil social...) — jamais un uid seul sans le profil_id réel.
--
-- Corrigé : can_review_pro() prend maintenant aussi p_client_profile_id et
-- exige qu'il corresponde à rdv.client_profile_id / comptes_rendus.
-- owner_profile_id — avec repli permissif SEULEMENT si l'un des deux côtés
-- n'a pas de profile_id renseigné (anciennes lignes créées avant ce champ).
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.can_review_pro(
  p_pro_uid TEXT,
  p_client_uid TEXT,
  p_client_profile_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM rdv
    WHERE rdv.pro_uid = p_pro_uid AND rdv.client_uid = p_client_uid
      AND rdv.statut IN ('confirme', 'termine')
      AND (p_client_profile_id IS NULL OR rdv.client_profile_id IS NULL OR rdv.client_profile_id = p_client_profile_id)
  ) OR EXISTS (
    SELECT 1 FROM comptes_rendus
    WHERE comptes_rendus.pro_uid = p_pro_uid AND comptes_rendus.owner_uid = p_client_uid
      AND (p_client_profile_id IS NULL OR comptes_rendus.owner_profile_id IS NULL OR comptes_rendus.owner_profile_id = p_client_profile_id)
  );
$$;
GRANT EXECUTE ON FUNCTION public.can_review_pro(TEXT, TEXT, UUID) TO anon, authenticated;

DROP POLICY IF EXISTS "avis_pro_insert" ON avis_pro;
CREATE POLICY "avis_pro_insert" ON avis_pro
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = client_uid
    AND public.can_review_pro(pro_uid, client_uid, client_profile_id)
  );

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename = 'avis_pro'
ORDER BY cmd;
