-- Coordonnées du client d'un RDV pour le professionnel de ce RDV (facture,
-- contrat, envoi des documents) : e-mail et téléphone du compte compris, que
-- le pro ne peut pas lire directement (colonnes privées) et que
-- pm_client_facturation ne donne qu'avec un partage du carnet de l'animal
-- (rarement le cas pour un toiletteur, un photographe…).
-- Réservé au pro du RDV (titulaire du compte ou employé actif du profil),
-- RDV non annulé / refusé. Aucune donnée pour un tiers.

CREATE OR REPLACE FUNCTION public.pm_contact_client_rdv(p_rdv_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub text := auth.jwt() ->> 'sub';
  r rdv%ROWTYPE;
  pf text; pl text; pm text; pt text; pt2 text; pr text; pc text; pv text;
  uf text; ul text; um text; ut text; ur text; uc text; uv text;
  v_ok boolean;
BEGIN
  IF v_sub IS NULL OR p_rdv_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO r FROM rdv WHERE id = p_rdv_id;
  IF NOT FOUND OR r.statut IN ('annule', 'refuse') OR r.client_uid IS NULL THEN RETURN NULL; END IF;
  v_ok := r.pro_uid = v_sub OR EXISTS (
    SELECT 1 FROM employes e
     WHERE e.eleveur_profile_id::text = r.pro_profile_id::text AND e.uid_employe = v_sub AND e.actif);
  IF NOT v_ok THEN RETURN NULL; END IF;

  -- Variables simples (un RECORD jamais affecté lèverait une erreur).
  IF r.client_profile_id IS NOT NULL THEN
    SELECT firstname, lastname, email_contact, phone_number, phone, rue, code_postal, ville
      INTO pf, pl, pm, pt, pt2, pr, pc, pv
      FROM user_profiles WHERE id::text = r.client_profile_id::text;
  END IF;
  SELECT firstname, lastname, email, phone_number, rue, code_postal, ville
    INTO uf, ul, um, ut, ur, uc, uv FROM users WHERE uid = r.client_uid;

  RETURN jsonb_build_object(
    'prenom', COALESCE(NULLIF(trim(pf), ''), NULLIF(trim(uf), ''), ''),
    'nom', COALESCE(NULLIF(trim(pl), ''), NULLIF(trim(ul), ''), ''),
    'email', COALESCE(NULLIF(trim(pm), ''), NULLIF(trim(um), ''), ''),
    'telephone', COALESCE(NULLIF(trim(pt), ''), NULLIF(trim(pt2), ''), NULLIF(trim(ut), ''), ''),
    'rue', COALESCE(NULLIF(trim(pr), ''), NULLIF(trim(ur), ''), ''),
    'code_postal', COALESCE(NULLIF(trim(pc), ''), NULLIF(trim(uc), ''), ''),
    'ville', COALESCE(NULLIF(trim(pv), ''), NULLIF(trim(uv), ''), '')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.pm_contact_client_rdv(uuid) FROM PUBLIC;
-- Requêtes Firebase en rôle anon (jeton vérifié côté Supabase).
GRANT EXECUTE ON FUNCTION public.pm_contact_client_rdv(uuid) TO anon, authenticated;
