-- ACACED : attestation de la formation d'actualisation (ACACED de plus de
-- 10 ans), distincte du certificat (acaced_doc_url) pour que l'admin voie les
-- deux pièces à la validation du profil. Colonne PRIVÉE comme acaced_doc_url
-- (soi, admin, relations légitimes) : ajoutée aux deux listes de colonnes
-- privées, puis vues régénérées. N'applique PAS pm_appliquer_droits_perso()
-- (état de la phase 2 inchangé ; si la phase 2 est en place, la colonne n'est
-- de toute façon pas lisible sur la table, seulement via la vue masquée).
-- À passer d'abord sur le staging. Idempotent.
BEGIN;

ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS acaced_actualisation_url TEXT;

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
    'arrete_prefectoral_url','acaced_actualisation_url','autre_domicile_adresse','autre_domicile_lat','autre_domicile_lng',
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

CREATE OR REPLACE FUNCTION public.pm_appliquer_droits_perso()
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  -- Mêmes listes que pm_recreer_vues_perso() (privées + contact).
  u_cachees text[] := ARRAY['email','date_of_birth','fcm_token','apns_token','stripe_customer_id',
    'cgu_accepted_at','is_admin','is_dev','valid_until','reminder_15_sent','reminder_21_sent',
    'rejection_reason','verification_status','kbis_url','acaced_doc_url','document_elevage',
    'extra_data','active_conversation_id','agenda_couleurs_types','garde_chevauchement_ok',
    'phone_number','code_iso','adress','rue','code_postal','lat','lng'];
  p_cachees text[] := ARRAY['date_of_birth','fcm_token','apns_token','stripe_customer_id',
    'cgu_accepted_at','iban_pro','bic_pro','validation_api_data','validation_reasons',
    'validation_score','rejection_reason','kbis_url','acaced_doc_url','diplome_url','statuts_url',
    'arrete_prefectoral_url','acaced_actualisation_url','autre_domicile_adresse','autre_domicile_lat','autre_domicile_lng',
    'trajet_origine_defaut','social_notif_seen_at',
    'phone','phone_number','telephone','email_contact','adresse','rue','code_postal','lat','lng',
    'latitude','longitude','rue_elevage','code_postal_elevage','adress_elevage','rue_pro',
    'code_postal_pro','lat_pro','lng_pro'];
  cols text;
BEGIN
  EXECUTE 'REVOKE SELECT ON public.users, public.user_profiles FROM anon, authenticated';

  SELECT string_agg(quote_ident(column_name), ', ') INTO cols
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'users' AND NOT (column_name = ANY (u_cachees));
  EXECUTE format('GRANT SELECT (%s) ON public.users TO anon, authenticated', cols);

  SELECT string_agg(quote_ident(column_name), ', ') INTO cols
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'user_profiles' AND NOT (column_name = ANY (p_cachees));
  EXECUTE format('GRANT SELECT (%s) ON public.user_profiles TO anon, authenticated', cols);

  NOTIFY pgrst, 'reload schema';
END;
$$;

SELECT public.pm_recreer_vues_perso();
NOTIFY pgrst, 'reload schema';
COMMIT;

-- Vérification (doit renvoyer la ligne : colonne masquée dans la vue) :
-- SELECT pg_get_viewdef('public.user_profiles_complet') LIKE '%CASE WHEN v.voit THEN t.acaced_actualisation_url%';

-- ROLLBACK
-- ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS acaced_actualisation_url;
-- SELECT public.pm_recreer_vues_perso();
