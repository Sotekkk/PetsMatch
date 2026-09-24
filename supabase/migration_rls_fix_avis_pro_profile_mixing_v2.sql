-- ══════════════════════════════════════════════════════════════════════════
-- Correctif v2 : mix de profil dans les DEUX sens (celui qui donne l'avis
-- ET celui qui le reçoit)
-- ══════════════════════════════════════════════════════════════════════════
-- Le correctif précédent (migration_rls_fix_avis_pro_profile_mixing.sql)
-- ne vérifiait le profil que du côté du CLIENT. Même bug côté PRO : un
-- compte pro peut avoir plusieurs profils métier (éleveur, véto,
-- toilettage, taxi… tous sous le même uid, cf. les comptes de test) — un
-- RDV pris avec le profil "véto" du compte rendrait à tort éligible un
-- avis sur le profil "toilettage" du MÊME compte, deux activités bien
-- distinctes aux yeux du client. can_review_pro() vérifie maintenant le
-- lien exact entre les DEUX profils (celui qui donne l'avis ET celui qui
-- le reçoit), plus seulement les deux comptes.
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
      AND (p_pro_profile_id IS NULL OR rdv.pro_profile_id IS NULL OR rdv.pro_profile_id = p_pro_profile_id)
  ) OR EXISTS (
    SELECT 1 FROM comptes_rendus
    WHERE comptes_rendus.pro_uid = p_pro_uid AND comptes_rendus.owner_uid = p_client_uid
      AND (p_client_profile_id IS NULL OR comptes_rendus.owner_profile_id IS NULL OR comptes_rendus.owner_profile_id = p_client_profile_id)
      AND (p_pro_profile_id IS NULL OR comptes_rendus.pro_profile_id IS NULL OR comptes_rendus.pro_profile_id = p_pro_profile_id)
  );
$$;
GRANT EXECUTE ON FUNCTION public.can_review_pro(TEXT, TEXT, UUID, UUID) TO anon, authenticated;

DROP POLICY IF EXISTS "avis_pro_insert" ON avis_pro;
CREATE POLICY "avis_pro_insert" ON avis_pro
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = client_uid
    AND public.can_review_pro(pro_uid, client_uid, client_profile_id, pro_profile_id)
  );

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename = 'avis_pro'
ORDER BY cmd;
