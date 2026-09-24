-- ══════════════════════════════════════════════════════════════════════════
-- Correctif : rdv.pro_profile_id est TEXT (pas UUID comme les autres
-- colonnes profile_id du projet) — comparaison échouait avec « operator
-- does not exist: text = uuid ».
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.can_review_pro(
  p_pro_uid TEXT,
  p_client_uid TEXT,
  p_client_profile_id UUID DEFAULT NULL,
  p_pro_profile_id UUID DEFAULT NULL
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
      AND (p_pro_profile_id IS NULL OR rdv.pro_profile_id IS NULL OR rdv.pro_profile_id = p_pro_profile_id::text)
  ) OR EXISTS (
    SELECT 1 FROM comptes_rendus
    WHERE comptes_rendus.pro_uid = p_pro_uid AND comptes_rendus.owner_uid = p_client_uid
      AND (p_client_profile_id IS NULL OR comptes_rendus.owner_profile_id IS NULL OR comptes_rendus.owner_profile_id = p_client_profile_id)
      AND (p_pro_profile_id IS NULL OR comptes_rendus.pro_profile_id IS NULL OR comptes_rendus.pro_profile_id = p_pro_profile_id)
  ) OR EXISTS (
    SELECT 1 FROM cessions
    WHERE cessions.uid_eleveur = p_pro_uid AND cessions.uid_acquereur = p_client_uid
      AND cessions.statut = 'confirme'
      AND (p_client_profile_id IS NULL OR cessions.acquereur_profile_id IS NULL OR cessions.acquereur_profile_id = p_client_profile_id)
      AND (p_pro_profile_id IS NULL OR cessions.pro_profile_id IS NULL OR cessions.pro_profile_id = p_pro_profile_id)
  );
$$;
GRANT EXECUTE ON FUNCTION public.can_review_pro(TEXT, TEXT, UUID, UUID) TO anon, authenticated;

-- Vérification
SELECT proname FROM pg_proc WHERE proname = 'can_review_pro';
