-- ════════════════════════════════════════════════════════════════════════
-- Données personnelles (users / user_profiles) — PHASE 1 : vues masquées.
-- N'enlève AUCUN droit : l'appli et le site actuels continuent de marcher.
-- Phase 2 (migration_donnees_perso_revoke.sql), APRÈS le passage du code
-- sur les vues : retrait du droit de lire les colonnes privées des tables.
--
-- Problème : users et user_profiles sont lisibles par tous (profils publics)
-- et contiennent e-mail, date de naissance, téléphone, adresse, GPS du
-- domicile, IBAN, liens KBIS / diplôme… Une policy RLS ne peut pas masquer
-- une colonne : on passe par des vues.
--
-- users_complet / user_profiles_complet : toutes les lignes, toutes les
-- colonnes, mais :
--   • colonnes TOUJOURS privées : visibles seulement si pm_voit_prive(uid) ;
--   • colonnes de CONTACT (téléphone, adresse, GPS, e-mail de contact) :
--     publiques pour un PRO (profil non particulier / compte élevage, pro,
--     association), privées pour un particulier ;
--   • le reste : public, inchangé.
-- Visibles : soi, admin, relations légitimes et cédant d'un lien de
-- signature — liste calculée UNE fois par requête (pm_uids_visibles).
-- Les vues sont générées depuis les colonnes des tables :
-- SELECT pm_recreer_vues_perso(); après tout ajout de colonne.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── Mon e-mail (pour les policies, sans lire users avec mes droits) ────
CREATE OR REPLACE FUNCTION public.pm_mon_email()
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT nullif(lower(email), '') FROM users WHERE uid = (auth.jwt() ->> 'sub');
$$;
GRANT EXECUTE ON FUNCTION public.pm_mon_email() TO anon, authenticated;

-- documents_animaux_write lisait users.email avec les droits de l'appelant.
DROP POLICY IF EXISTS documents_animaux_write ON public.documents_animaux;
CREATE POLICY documents_animaux_write ON public.documents_animaux
  FOR ALL TO public
  USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (SELECT 1 FROM elevage_cogerants c
               WHERE c.uid_gerant = documents_animaux.uid_eleveur
                 AND c.uid_cogerant = (auth.jwt() ->> 'sub')
                 AND c.statut = 'actif' AND c.date_fin IS NULL)
    OR lower(metadata ->> 'acquereur_email') = public.pm_mon_email()
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (SELECT 1 FROM elevage_cogerants c
               WHERE c.uid_gerant = documents_animaux.uid_eleveur
                 AND c.uid_cogerant = (auth.jwt() ->> 'sub')
                 AND c.statut = 'actif' AND c.date_fin IS NULL)
    OR lower(metadata ->> 'acquereur_email') = public.pm_mon_email()
  );

-- ── Personnes dont je peux voir les données privées ────────────────────
-- Calculé UNE fois par requête (la vue l'appelle hors de la boucle des
-- lignes) : moi + mes relations légitimes + le cédant d'un lien de
-- signature. « moi » = mon uid + les comptes pour lesquels j'agis
-- (employeurs actifs, gérants dont je suis cogérant actif) : l'employé
-- d'une pension voit le téléphone des clients de la pension.
CREATE OR REPLACE FUNCTION public.pm_uids_visibles()
RETURNS text[]
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub text := auth.jwt() ->> 'sub';
  v_tok text := public.pm_token_requete();
  v_moi text[];
  v_res text[];
BEGIN
  IF v_sub IS NULL AND v_tok IS NULL THEN RETURN '{}'; END IF;
  v_moi := ARRAY[v_sub]
    || coalesce((SELECT array_agg(DISTINCT e.uid_eleveur) FROM employes e
                 WHERE e.uid_employe = v_sub AND e.actif), '{}')
    || coalesce((SELECT array_agg(DISTINCT c.uid_gerant) FROM elevage_cogerants c
                 WHERE c.uid_cogerant = v_sub AND c.statut = 'actif' AND c.date_fin IS NULL), '{}');

  SELECT array_agg(DISTINCT u) INTO v_res FROM (
      SELECT v_sub AS u
      -- équipe
      UNION SELECT e.uid_employe FROM employes e WHERE e.actif AND e.uid_eleveur = ANY (v_moi)
      UNION SELECT e.uid_eleveur FROM employes e WHERE e.actif AND e.uid_employe = v_sub
      UNION SELECT c.uid_cogerant FROM elevage_cogerants c WHERE c.statut = 'actif' AND c.date_fin IS NULL AND c.uid_gerant = ANY (v_moi)
      UNION SELECT c.uid_gerant FROM elevage_cogerants c WHERE c.statut = 'actif' AND c.date_fin IS NULL AND c.uid_cogerant = v_sub
      -- pro ↔ client, élevage ↔ acquéreur, association ↔ famille d'accueil
      UNION SELECT x.client_uid FROM rdv x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM rdv x WHERE x.client_uid = v_sub
      UNION SELECT x.client_uid FROM devis x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM devis x WHERE x.client_uid = v_sub
      UNION SELECT x.client_uid FROM factures x WHERE x.uid_eleveur = ANY (v_moi)
      UNION SELECT x.uid_eleveur FROM factures x WHERE x.client_uid = v_sub
      UNION SELECT x.proprietaire_uid FROM pension_factures x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM pension_factures x WHERE x.proprietaire_uid = v_sub
      UNION SELECT x.client_uid FROM albums_photo x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM albums_photo x WHERE x.client_uid = v_sub
      UNION SELECT x.client_uid FROM fiches_toilettage x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM fiches_toilettage x WHERE x.client_uid = v_sub
      UNION SELECT x.client_uid FROM forfaits_souscrits x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM forfaits_souscrits x WHERE x.client_uid = v_sub
      UNION SELECT x.client_uid FROM photographe_factures x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM photographe_factures x WHERE x.client_uid = v_sub
      UNION SELECT x.client_uid FROM taxi_factures x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM taxi_factures x WHERE x.client_uid = v_sub
      UNION SELECT x.client_uid FROM toilettage_factures x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM toilettage_factures x WHERE x.client_uid = v_sub
      UNION SELECT x.owner_uid FROM animal_acces_pro x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM animal_acces_pro x WHERE x.owner_uid = v_sub
      UNION SELECT x.owner_uid FROM cles_clients x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM cles_clients x WHERE x.owner_uid = v_sub
      UNION SELECT x.owner_uid FROM comptes_rendus x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM comptes_rendus x WHERE x.owner_uid = v_sub
      UNION SELECT x.owner_uid FROM education_attestations x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM education_attestations x WHERE x.owner_uid = v_sub
      UNION SELECT x.owner_uid FROM education_objectifs x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM education_objectifs x WHERE x.owner_uid = v_sub
      UNION SELECT x.owner_uid FROM education_progression x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM education_progression x WHERE x.owner_uid = v_sub
      UNION SELECT x.owner_uid FROM exercices_attribues x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM exercices_attribues x WHERE x.owner_uid = v_sub
      UNION SELECT x.owner_uid FROM ordonnances x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM ordonnances x WHERE x.owner_uid = v_sub
      UNION SELECT x.owner_uid FROM pension_acces x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM pension_acces x WHERE x.owner_uid = v_sub
      UNION SELECT x.owner_uid FROM tarifs_clients_garde x WHERE x.pro_uid = ANY (v_moi)
      UNION SELECT x.pro_uid FROM tarifs_clients_garde x WHERE x.owner_uid = v_sub
      UNION SELECT x.uid_acquereur FROM cessions x WHERE x.uid_eleveur = ANY (v_moi)
      UNION SELECT x.uid_eleveur FROM cessions x WHERE x.uid_acquereur = v_sub
      UNION SELECT x.uid_acquereur FROM documents_animaux x WHERE x.uid_eleveur = ANY (v_moi)
      UNION SELECT x.uid_eleveur FROM documents_animaux x WHERE x.uid_acquereur = v_sub
      UNION SELECT x.acquereur_uid FROM certificats_engagement x WHERE x.cedant_uid = ANY (v_moi)
      UNION SELECT x.cedant_uid FROM certificats_engagement x WHERE x.acquereur_uid = v_sub
      UNION SELECT x.uid_acquereur FROM reservations_animaux x WHERE x.uid_eleveur = ANY (v_moi)
      UNION SELECT x.uid_eleveur FROM reservations_animaux x WHERE x.uid_acquereur = v_sub
      UNION SELECT x.owner_uid FROM animaux x WHERE x.uid_eleveur = ANY (v_moi)
      UNION SELECT x.uid_eleveur FROM animaux x WHERE x.owner_uid = v_sub
      UNION SELECT x.uid_acquereur FROM animaux x WHERE x.uid_eleveur = ANY (v_moi)
      UNION SELECT x.uid_eleveur FROM animaux x WHERE x.uid_acquereur = v_sub
      UNION SELECT x.fa_uid FROM familles_accueil x WHERE x.association_uid = ANY (v_moi)
      UNION SELECT x.association_uid FROM familles_accueil x WHERE x.fa_uid = v_sub
      -- animal en pension chez moi → son propriétaire
      UNION SELECT ap.uid_proprio FROM pension_entrees pe JOIN animaux_proprietes ap ON ap.animal_id = pe.animal_id WHERE pe.pro_uid = ANY (v_moi)
      UNION SELECT pe.pro_uid FROM pension_entrees pe JOIN animaux_proprietes ap ON ap.animal_id = pe.animal_id WHERE ap.uid_proprio = v_sub
      -- accès d'un pro au dossier d'un animal (profils)
      UNION SELECT po.uid FROM animal_access aa JOIN user_profiles pp ON pp.id = aa.pro_profile_id
            JOIN user_profiles po ON po.id = aa.granted_by_profile_id
            WHERE aa.statut = 'active' AND pp.uid = ANY (v_moi)
      UNION SELECT pp.uid FROM animal_access aa JOIN user_profiles pp ON pp.id = aa.pro_profile_id
            JOIN user_profiles po ON po.id = aa.granted_by_profile_id
            WHERE aa.statut = 'active' AND po.uid = v_sub
      -- co-propriétaires d'un même animal
      UNION SELECT a2.uid_proprio FROM animaux_proprietes a1 JOIN animaux_proprietes a2 ON a2.animal_id = a1.animal_id
            WHERE a1.uid_proprio = v_sub
      -- lien de signature : le vendeur / cédant du document
      UNION SELECT c.uid_eleveur FROM cessions c WHERE v_tok IS NOT NULL AND c.token = v_tok
      UNION SELECT d.uid_eleveur FROM documents_animaux d WHERE v_tok IS NOT NULL AND d.token = v_tok
      UNION SELECT ce.cedant_uid FROM certificats_engagement ce WHERE v_tok IS NOT NULL AND ce.token_signature = v_tok
  ) s WHERE u IS NOT NULL;
  RETURN coalesce(v_res, '{}');
END;
$$;
GRANT EXECUTE ON FUNCTION public.pm_uids_visibles() TO anon, authenticated;

-- Contrôle ponctuel (une personne) — même règle que les vues.
CREATE OR REPLACE FUNCTION public.pm_voit_prive(p_uid text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_uid IS NOT NULL AND (
    public.is_admin_uid(auth.jwt() ->> 'sub') OR p_uid = ANY (public.pm_uids_visibles()));
$$;
GRANT EXECUTE ON FUNCTION public.pm_voit_prive(text) TO anon, authenticated;

-- ── Génération des vues masquées ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.pm_recreer_vues_perso()
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  u_prive text[] := ARRAY['email','date_of_birth','fcm_token','apns_token','stripe_customer_id',
    'cgu_accepted_at','is_admin','is_dev','valid_until','reminder_15_sent','reminder_21_sent',
    'rejection_reason','verification_status','kbis_url','acaced_doc_url','document_elevage',
    'extra_data','active_conversation_id','agenda_couleurs_types','garde_chevauchement_ok'];
  u_contact text[] := ARRAY['phone_number','code_iso','adress','rue','code_postal','lat','lng'];
  p_prive text[] := ARRAY['date_of_birth','fcm_token','apns_token','stripe_customer_id',
    'cgu_accepted_at','iban_pro','bic_pro','validation_api_data','validation_reasons',
    'validation_score','rejection_reason','kbis_url','acaced_doc_url','diplome_url','statuts_url',
    'arrete_prefectoral_url','autre_domicile_adresse','autre_domicile_lat','autre_domicile_lng',
    'trajet_origine_defaut','social_notif_seen_at'];
  p_contact text[] := ARRAY['phone','phone_number','telephone','email_contact','adresse','rue',
    'code_postal','lat','lng','latitude','longitude','rue_elevage','code_postal_elevage',
    'adress_elevage','rue_pro','code_postal_pro','lat_pro','lng_pro'];
  cols text;
BEGIN
  SELECT string_agg(
           CASE WHEN column_name = ANY (u_prive) THEN format('CASE WHEN v.voit THEN t.%1$I END AS %1$I', column_name)
                WHEN column_name = ANY (u_contact) THEN format('CASE WHEN v.voit OR v.pro THEN t.%1$I END AS %1$I', column_name)
                ELSE format('t.%I', column_name) END, ', ' ORDER BY ordinal_position)
    INTO cols
    FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users';
  EXECUTE 'DROP VIEW IF EXISTS public.users_complet';
  EXECUTE format($v$CREATE VIEW public.users_complet WITH (security_barrier) AS
    SELECT %s FROM public.users t
    -- (SELECT …) scalaires non corrélés : évalués UNE fois (InitPlan), pas
    -- pour chaque ligne.
    CROSS JOIN LATERAL (SELECT ((SELECT public.is_admin_uid(auth.jwt() ->> 'sub'))
                                OR ARRAY[t.uid] <@ (SELECT public.pm_uids_visibles())) AS voit,
      (coalesce(t.is_elevage, false) OR coalesce(t.is_pro, false) OR coalesce(t.is_association, false)) AS pro) v$v$, cols);

  SELECT string_agg(
           CASE WHEN column_name = ANY (p_prive) THEN format('CASE WHEN v.voit THEN t.%1$I END AS %1$I', column_name)
                WHEN column_name = ANY (p_contact) THEN format('CASE WHEN v.voit OR v.pro THEN t.%1$I END AS %1$I', column_name)
                ELSE format('t.%I', column_name) END, ', ' ORDER BY ordinal_position)
    INTO cols
    FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'user_profiles';
  EXECUTE 'DROP VIEW IF EXISTS public.user_profiles_complet';
  EXECUTE format($v$CREATE VIEW public.user_profiles_complet WITH (security_barrier) AS
    SELECT %s FROM public.user_profiles t
    -- (SELECT …) scalaires non corrélés : évalués UNE fois (InitPlan), pas
    -- pour chaque ligne.
    CROSS JOIN LATERAL (SELECT ((SELECT public.is_admin_uid(auth.jwt() ->> 'sub'))
                                OR ARRAY[t.uid] <@ (SELECT public.pm_uids_visibles())) AS voit,
      (t.profile_type IS DISTINCT FROM 'particulier') AS pro) v$v$, cols);

  EXECUTE 'GRANT SELECT ON public.users_complet, public.user_profiles_complet TO anon, authenticated';
  -- Recharge le cache de schéma PostgREST.
  NOTIFY pgrst, 'reload schema';
END;
$$;

SELECT public.pm_recreer_vues_perso();

-- ── Recherche d'un utilisateur par e-mail / téléphone EXACT ────────────
-- Remplace les recherches directes sur users.email (eq / ilike) : ne
-- renvoie que l'identité publique, et seulement sur correspondance exacte
-- (plus d'énumération des e-mails par « contient »).
CREATE OR REPLACE FUNCTION public.pm_trouver_utilisateur(p_email text DEFAULT NULL, p_telephone text DEFAULT NULL)
RETURNS TABLE (uid text, firstname text, lastname text, name_elevage text,
               profile_picture_url text, is_elevage boolean, is_pro boolean, is_association boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT u.uid, u.firstname, u.lastname, u.name_elevage, u.profile_picture_url,
         u.is_elevage, u.is_pro, u.is_association
  FROM users u
  WHERE (auth.jwt() ->> 'sub') IS NOT NULL
    AND (
      (nullif(trim(p_email), '') IS NOT NULL AND lower(u.email) = lower(trim(p_email)))
      OR (length(regexp_replace(coalesce(p_telephone, ''), '\D', '', 'g')) >= 9
          AND right(regexp_replace(coalesce(u.phone_number, ''), '\D', '', 'g'), 9)
              = right(regexp_replace(p_telephone, '\D', '', 'g'), 9))
    )
  LIMIT 5;
$$;
GRANT EXECUTE ON FUNCTION public.pm_trouver_utilisateur(text, text) TO anon, authenticated;

COMMIT;
