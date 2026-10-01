-- ════════════════════════════════════════════════════════════════════════
-- Données personnelles (users / user_profiles) — PHASE 2 : retrait du droit
-- de LIRE directement les colonnes privées et de contact des tables.
--
-- ⚠ À appliquer seulement quand l'appli ET le site lisent via les vues
--   users_complet / user_profiles_complet (commit d2b26315) — une ancienne
--   version (select('*') sur les tables) recevra « permission denied ».
--
-- Après : lecture directe des tables limitée aux colonnes publiques ; les
-- colonnes privées / de contact ne se lisent plus que par les vues masquées
-- (pm_uids_visibles) ou en service_role. Écritures inchangées.
-- La liste est recalculée par pm_appliquer_droits_perso() (à relancer
-- après tout ajout de colonne, avec pm_recreer_vues_perso()).
--
-- Retour arrière : GRANT SELECT ON public.users, public.user_profiles
--                  TO anon, authenticated;
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

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
    'arrete_prefectoral_url','autre_domicile_adresse','autre_domicile_lat','autre_domicile_lng',
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

SELECT public.pm_appliquer_droits_perso();

COMMIT;
