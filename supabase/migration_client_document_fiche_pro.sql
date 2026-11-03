-- Client des factures / documents : jamais le professionnel qui a créé la
-- fiche (03/11/2026).
--
-- Constat : facture du vétérinaire pour un client sans compte dont la fiche
-- avait été créée par l'ostéopathe → « Client : Cabinet Ostéo Test » (le pro
-- créateur, titulaire de la fiche) au lieu du client. Même défaut sur les
-- coordonnées des CR / ordonnances (même fonction).
--
--   • pm_client_facturation : fiche créée par un pro et sans propriétaire
--     PetsMatch → client du fichier clients (clients_clinique : nom, adresse,
--     e-mail, téléphone) ; sinon rien (l'appelant prend le client du RDV) ;
--   • pm_contact_client_rdv (éducateur, toilettage, forfaits…) : client sans
--     compte → fichier clients de la fiche (adresse comprise), complété par
--     les coordonnées saisies sur le RDV.
-- Le reste des deux fonctions est inchangé. Idempotent.

BEGIN;

CREATE OR REPLACE FUNCTION public.pm_client_facturation(p_animal_id text, p_client_profile_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sub     TEXT := auth.jwt() ->> 'sub';
  v_uid     TEXT;
  v_profil  TEXT;
  p         RECORD;
  u         RECORD;
  v_type    TEXT;
  v_societe BOOLEAN;
  v_cree    TEXT;
  v_cc      TEXT;
  v_prop    TEXT;
  c         RECORD;
BEGIN
  IF v_sub IS NULL OR p_animal_id IS NULL THEN RETURN NULL; END IF;

  -- Accès : partage actif avec un profil de l'appelant, ou employé actif.
  IF NOT EXISTS (
    SELECT 1 FROM animal_access aa
    JOIN user_profiles up ON up.id::text = aa.pro_profile_id::text
    WHERE aa.animal_id::text = p_animal_id AND aa.statut = 'active'
      AND (up.uid::text = v_sub OR EXISTS (
        SELECT 1 FROM employes e
        WHERE e.eleveur_profile_id::text = up.id::text AND e.uid_employe::text = v_sub AND e.actif))
  ) THEN
    RETURN NULL;
  END IF;

  -- Client du RDV (ex. co-propriétaire qui a amené l'animal), s'il est bien
  -- propriétaire actif de l'animal ; sinon propriétaire principal, sinon
  -- propriétaire / éleveur de la fiche.
  IF p_client_profile_id IS NOT NULL THEN
    SELECT ap.uid_proprio::text, ap.profile_id_proprio::text INTO v_uid, v_profil
      FROM animaux_proprietes ap
     WHERE ap.animal_id::text = p_animal_id AND ap.profile_id_proprio::text = p_client_profile_id::text
       AND ap.statut = 'actif' AND ap.date_fin IS NULL
     LIMIT 1;
  END IF;
  IF v_uid IS NULL THEN
  SELECT ap.uid_proprio::text, ap.profile_id_proprio::text INTO v_uid, v_profil
    FROM animaux_proprietes ap
   WHERE ap.animal_id::text = p_animal_id AND ap.role_proprio = 'principal'
     AND ap.statut = 'actif' AND ap.date_fin IS NULL
   LIMIT 1;
  END IF;
  -- Fiche créée par un professionnel (client sans compte PetsMatch, ou pas
  -- encore rattaché) : le client est celui du fichier clients — jamais le
  -- professionnel qui a créé la fiche (il figurait comme « client » sur les
  -- factures, CR et ordonnances des autres pros).
  IF v_uid IS NULL THEN
    SELECT a.cree_par_pro_profile_id::text, a.client_clinique_id::text, a.uid_proprietaire::text
      INTO v_cree, v_cc, v_prop FROM animaux a WHERE a.id::text = p_animal_id;
    IF v_cree IS NOT NULL AND v_prop IS NULL THEN
      IF v_cc IS NOT NULL THEN
        SELECT * INTO c FROM clients_clinique WHERE id::text = v_cc;
        IF FOUND THEN
          RETURN jsonb_build_object(
            'type', 'particulier', 'societe', false,
            'prenom', COALESCE(NULLIF(trim(c.prenom), ''), ''), 'nom', COALESCE(NULLIF(trim(c.nom), ''), ''),
            'rue', COALESCE(NULLIF(trim(c.adresse), ''), ''), 'code_postal', COALESCE(NULLIF(trim(c.code_postal), ''), ''),
            'ville', COALESCE(NULLIF(trim(c.ville), ''), ''), 'pays', '',
            'email', COALESCE(NULLIF(trim(c.email), ''), ''), 'telephone', COALESCE(NULLIF(trim(c.telephone), ''), ''),
            'siret', '', 'numero_tva', '', 'client_clinique', true);
        END IF;
      END IF;
      RETURN NULL;
    END IF;
  END IF;
  IF v_uid IS NULL THEN
    SELECT COALESCE(a.uid_proprietaire, a.uid_eleveur)::text, a.profile_id::text INTO v_uid, v_profil
      FROM animaux a WHERE a.id::text = p_animal_id;
  END IF;
  IF v_uid IS NULL THEN RETURN NULL; END IF;

  -- (FOUND plutôt que « p IS NULL » : un RECORD jamais affecté lève une erreur.)
  IF v_profil IS NOT NULL THEN
    SELECT * INTO p FROM user_profiles WHERE id::text = v_profil;
  END IF;
  IF v_profil IS NULL OR NOT FOUND THEN
    SELECT * INTO p FROM user_profiles WHERE uid::text = v_uid AND is_main = true LIMIT 1;
    IF NOT FOUND THEN
      SELECT * INTO p FROM user_profiles WHERE uid::text = v_uid ORDER BY created_at LIMIT 1;
      IF NOT FOUND THEN RETURN NULL; END IF;
    END IF;
  END IF;
  SELECT firstname, lastname, email, phone_number, rue, code_postal, ville,
         name_elevage, rue_elevage, code_postal_elevage, ville_elevage, siret
    INTO u FROM users WHERE uid::text = v_uid;

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
    -- Contact du client (e-mail de contact, sinon celui du compte ; téléphone
    -- du profil, sinon du compte) — transmis seulement au pro qui a un
    -- partage actif de l'animal (contrôle d'accès ci-dessus).
    'email', COALESCE(NULLIF(trim(p.email_contact), ''), NULLIF(trim(u.email), ''), ''),
    'telephone', COALESCE(NULLIF(trim(p.phone_number), ''), NULLIF(trim(p.phone), ''), NULLIF(trim(p.telephone), ''),
                          NULLIF(trim(u.phone_number), ''), ''),
    'siret', CASE WHEN v_societe THEN COALESCE(NULLIF(trim(p.siret), ''), NULLIF(trim(u.siret), ''), '') ELSE '' END,
    'numero_tva', CASE WHEN v_societe THEN COALESCE(NULLIF(trim(p.numero_tva), ''), '') ELSE '' END
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.pm_contact_client_rdv(p_rdv_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sub text := auth.jwt() ->> 'sub';
  r rdv%ROWTYPE;
  pf text; pl text; pm text; pt text; pt2 text; pr text; pc text; pv text;
  uf text; ul text; um text; ut text; ur text; uc text; uv text;
  v_ok boolean;
  c record;
BEGIN
  IF v_sub IS NULL OR p_rdv_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO r FROM rdv WHERE id = p_rdv_id;
  IF NOT FOUND OR r.statut IN ('annule', 'refuse') THEN RETURN NULL; END IF;
  v_ok := r.pro_uid = v_sub OR EXISTS (
    SELECT 1 FROM employes e
     WHERE e.eleveur_profile_id::text = r.pro_profile_id::text AND e.uid_employe = v_sub AND e.actif);
  IF NOT v_ok THEN RETURN NULL; END IF;
  -- Client sans compte PetsMatch : coordonnées du fichier clients de la fiche
  -- de l'animal (adresse comprise), complétées par celles saisies sur le RDV.
  IF r.client_uid IS NULL THEN
    SELECT cc.* INTO c FROM animaux a JOIN clients_clinique cc ON cc.id = a.client_clinique_id
     WHERE a.id::text = r.animal_id::text;
    IF NOT FOUND THEN RETURN NULL; END IF;
    RETURN jsonb_build_object(
      'prenom', COALESCE(NULLIF(trim(c.prenom), ''), ''),
      'nom', COALESCE(NULLIF(trim(c.nom), ''), NULLIF(trim(r.client_nom_manuel), ''), ''),
      'email', COALESCE(NULLIF(trim(c.email), ''), NULLIF(trim(r.client_email_manuel), ''), ''),
      'telephone', COALESCE(NULLIF(trim(c.telephone), ''), NULLIF(trim(r.client_telephone_manuel), ''), ''),
      'rue', COALESCE(NULLIF(trim(c.adresse), ''), ''),
      'code_postal', COALESCE(NULLIF(trim(c.code_postal), ''), ''),
      'ville', COALESCE(NULLIF(trim(c.ville), ''), '')
    );
  END IF;
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
$function$;

NOTIFY pgrst, 'reload schema';

COMMIT;
