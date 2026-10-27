-- ════════════════════════════════════════════════════════════════════════
-- Facture de consultation : facturer le CLIENT DU RDV.
--
-- Complément de migration_client_facturation.sql. Un co-propriétaire qui
-- amène l'animal (RDV pris par lui) doit être le client de la facture, pas
-- forcément le propriétaire principal. pm_client_facturation accepte
-- p_client_profile_id (client du RDV) : retenu s'il est propriétaire actif de
-- l'animal (animaux_proprietes), sinon propriétaire principal comme avant.
-- Même contrôle d'accès (partage actif de l'animal). Idempotent.
-- ════════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.pm_client_facturation(TEXT);

CREATE OR REPLACE FUNCTION public.pm_client_facturation(p_animal_id TEXT, p_client_profile_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_sub     TEXT := auth.jwt() ->> 'sub';
  v_uid     TEXT;
  v_profil  UUID;
  p         RECORD;
  u         RECORD;
  v_type    TEXT;
  v_societe BOOLEAN;
BEGIN
  IF v_sub IS NULL OR p_animal_id IS NULL THEN RETURN NULL; END IF;

  -- Accès : partage actif avec un profil de l'appelant, ou employé actif.
  IF NOT EXISTS (
    SELECT 1 FROM animal_access aa
    JOIN user_profiles up ON up.id = aa.pro_profile_id
    WHERE aa.animal_id = p_animal_id AND aa.statut = 'active'
      AND (up.uid = v_sub OR EXISTS (
        SELECT 1 FROM employes e
        WHERE e.eleveur_profile_id = up.id AND e.uid_employe = v_sub AND e.actif))
  ) THEN
    RETURN NULL;
  END IF;

  -- Client du RDV (ex. co-propriétaire qui a amené l'animal), s'il est bien
  -- propriétaire actif de l'animal ; sinon propriétaire principal, sinon
  -- propriétaire / éleveur de la fiche.
  IF p_client_profile_id IS NOT NULL THEN
    SELECT ap.uid_proprio, ap.profile_id_proprio INTO v_uid, v_profil
      FROM animaux_proprietes ap
     WHERE ap.animal_id = p_animal_id AND ap.profile_id_proprio = p_client_profile_id
       AND ap.statut = 'actif' AND ap.date_fin IS NULL
     LIMIT 1;
  END IF;
  IF v_uid IS NULL THEN
  SELECT ap.uid_proprio, ap.profile_id_proprio INTO v_uid, v_profil
    FROM animaux_proprietes ap
   WHERE ap.animal_id = p_animal_id AND ap.role_proprio = 'principal'
     AND ap.statut = 'actif' AND ap.date_fin IS NULL
   LIMIT 1;
  END IF;
  IF v_uid IS NULL THEN
    SELECT COALESCE(a.uid_proprietaire, a.uid_eleveur), a.profile_id INTO v_uid, v_profil
      FROM animaux a WHERE a.id = p_animal_id;
  END IF;
  IF v_uid IS NULL THEN RETURN NULL; END IF;

  -- (FOUND plutôt que « p IS NULL » : un RECORD jamais affecté lève une erreur.)
  IF v_profil IS NOT NULL THEN
    SELECT * INTO p FROM user_profiles WHERE id = v_profil;
  END IF;
  IF v_profil IS NULL OR NOT FOUND THEN
    SELECT * INTO p FROM user_profiles WHERE uid = v_uid AND is_main = true LIMIT 1;
    IF NOT FOUND THEN
      SELECT * INTO p FROM user_profiles WHERE uid = v_uid ORDER BY created_at LIMIT 1;
      IF NOT FOUND THEN RETURN NULL; END IF;
    END IF;
  END IF;
  SELECT firstname, lastname, email, phone_number, rue, code_postal, ville,
         name_elevage, rue_elevage, code_postal_elevage, ville_elevage, siret
    INTO u FROM users WHERE uid = v_uid;

  v_type := COALESCE(p.profile_type, 'particulier');
  v_societe := v_type <> 'particulier';

  RETURN jsonb_build_object(
    'type', v_type,
    'societe', v_societe,
    'prenom', CASE WHEN v_societe THEN '' ELSE COALESCE(NULLIF(trim(p.firstname), ''), NULLIF(trim(u.firstname), ''), '') END,
    'nom', CASE WHEN v_societe
      THEN COALESCE(NULLIF(trim(p.nom), ''), NULLIF(trim(p.nom_cabinet), ''), NULLIF(trim(u.name_elevage), ''),
                    trim(COALESCE(p.firstname, u.firstname, '') || ' ' || COALESCE(p.lastname, u.lastname, '')))
      ELSE COALESCE(NULLIF(trim(p.lastname), ''), NULLIF(trim(u.lastname), ''), NULLIF(trim(p.nom), ''), '') END,
    'rue', COALESCE(NULLIF(trim(p.rue_pro), ''), NULLIF(trim(p.rue), ''), NULLIF(trim(p.rue_elevage), ''),
                    NULLIF(trim(u.rue), ''), NULLIF(trim(u.rue_elevage), ''), ''),
    'code_postal', COALESCE(NULLIF(trim(p.code_postal_pro), ''), NULLIF(trim(p.code_postal), ''), NULLIF(trim(p.code_postal_elevage), ''),
                            NULLIF(trim(u.code_postal), ''), NULLIF(trim(u.code_postal_elevage), ''), ''),
    'ville', COALESCE(NULLIF(trim(p.ville_pro), ''), NULLIF(trim(p.ville), ''), NULLIF(trim(p.ville_elevage), ''),
                      NULLIF(trim(u.ville), ''), NULLIF(trim(u.ville_elevage), ''), ''),
    'pays', COALESCE(NULLIF(trim(p.pays_pro), ''), NULLIF(trim(p.pays), ''), ''),
    -- Particulier : e-mail / téléphone restent privés (non requis sur une facture).
    'email', CASE WHEN v_societe THEN COALESCE(NULLIF(trim(p.email_contact), ''), NULLIF(trim(u.email), ''), '') ELSE '' END,
    'telephone', CASE WHEN v_societe THEN COALESCE(NULLIF(trim(p.phone_number), ''), NULLIF(trim(p.phone), ''), NULLIF(trim(p.telephone), ''),
                          NULLIF(trim(u.phone_number), ''), '') ELSE '' END,
    'siret', CASE WHEN v_societe THEN COALESCE(NULLIF(trim(p.siret), ''), NULLIF(trim(u.siret), ''), '') ELSE '' END,
    'numero_tva', CASE WHEN v_societe THEN COALESCE(NULLIF(trim(p.numero_tva), ''), '') ELSE '' END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.pm_client_facturation(TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pm_client_facturation(TEXT, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
