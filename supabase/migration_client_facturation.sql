-- ════════════════════════════════════════════════════════════════════════
-- Facture d'un professionnel (vétérinaire…) : coordonnées du propriétaire.
--
-- Les coordonnées d'un particulier (rue, CP, ville, téléphone, e-mail) sont
-- masquées dans user_profiles_complet pour les autres comptes : la facture
-- proposée après une consultation n'avait que « Prénom Nom » dans le champ
-- Nom, sans adresse. Une facture doit porter l'identité et l'adresse du
-- client.
--
-- pm_client_facturation(animal) renvoie les coordonnées de facturation du
-- propriétaire principal SI l'appelant a un partage actif de l'animal
-- (animal_access avec un de ses profils, ou employé actif de ce profil) —
-- même règle d'accès que le carnet de santé. Sinon NULL.
--   type     : particulier | eleveur | association | autre type de profil
--   societe  : vrai pour un élevage / une association / un pro (nom = structure)
--   prenom, nom, rue, code_postal, ville, pays, siret, numero_tva ;
--   email / telephone : seulement pour un élevage / une association / un pro
--   (coordonnées d'un particulier : privées, non requises sur une facture)
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.pm_client_facturation(p_animal_id TEXT)
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

  -- Propriétaire principal, sinon propriétaire / éleveur de la fiche.
  SELECT ap.uid_proprio, ap.profile_id_proprio INTO v_uid, v_profil
    FROM animaux_proprietes ap
   WHERE ap.animal_id = p_animal_id AND ap.role_proprio = 'principal'
     AND ap.statut = 'actif' AND ap.date_fin IS NULL
   LIMIT 1;
  IF v_uid IS NULL THEN
    SELECT COALESCE(a.uid_proprietaire, a.uid_eleveur), a.profile_id INTO v_uid, v_profil
      FROM animaux a WHERE a.id = p_animal_id;
  END IF;
  IF v_uid IS NULL THEN RETURN NULL; END IF;

  IF v_profil IS NOT NULL THEN
    SELECT * INTO p FROM user_profiles WHERE id = v_profil;
  END IF;
  IF p IS NULL THEN
    SELECT * INTO p FROM user_profiles WHERE uid = v_uid AND is_main = true LIMIT 1;
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

REVOKE ALL ON FUNCTION public.pm_client_facturation(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pm_client_facturation(TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
