-- ════════════════════════════════════════════════════════════════════════
-- RLS user_profiles + colonnes réservées + essai gratuit réparé.
--
-- Avant :
--   • user_profiles_all (ALL true), user_profiles_anon_insert (true),
--     user_profiles_anon_update (true) annulaient les policies propriétaire
--     → n'importe qui, sans compte, créait / modifiait n'importe quel profil ;
--   • même en propriétaire, rien n'empêchait de s'attribuer plan_code /
--     is_premium / statut_pro = 'actif' / is_validate / is_influencer
--     (abonnement gratuit, vérification contournée) ;
--   • cogérant : pouvait modifier TOUS les profils du gérant (particulier,
--     pension…), pas seulement l'élevage de sa cogérance (mélange de profils) ;
--   • essai gratuit 30 j (trigger grant_trial_on_new_pro_profile, 14/09) :
--     JAMAIS accordé en prod — le trigger s'exécute avec les droits de
--     l'utilisateur, qui ne peut pas écrire dans `abonnements` ; l'erreur
--     était avalée (0 ligne essai_gratuit en base).
--
-- Après :
--   • lecture : publique (inchangé — profils publics) ;
--   • création : son propre profil (uid = soi) ;
--   • modification : propriétaire ; cogérant actif limité au profil élevage
--     de sa cogérance (repli sur l'uid si la cogérance n'a pas de profil) ;
--     admin ;
--   • suppression : propriétaire ou admin ;
--   • colonnes réservées (plan_code, is_premium, plan_until, is_influencer,
--     statut_pro, is_validate, rejection_reason) : un utilisateur non admin
--     ne peut que demander la vérification (statut_pro → 'en_attente'),
--     valider un profil particulier, repasser à « free ». Toute autre valeur
--     est ramenée à l'ancienne, sans erreur (les écrans renvoient souvent le
--     profil entier). Serveur (service_role), SQL et triggers système : libres ;
--   • essai gratuit : le trigger tourne en SECURITY DEFINER et prévient les
--     protections (drapeau pm.systeme) → l'essai est enfin accordé.
--
-- ⚠ Le site en ligne au 30/09 n'envoie pas le jeton Firebase : édition de
--   profil et inscription sur le site ne marcheront qu'une fois redéployé.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. Colonnes réservées ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.user_profiles_protege_colonnes()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- Serveur (service_role), SQL direct, triggers SECURITY DEFINER.
  IF current_user NOT IN ('anon', 'authenticated')
     OR current_setting('pm.systeme', true) = 'on'
     OR public.is_admin_uid(auth.jwt() ->> 'sub') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.plan_code        := 'free';
    NEW.is_premium       := false;
    NEW.plan_until       := NULL;
    NEW.is_influencer    := false;
    NEW.rejection_reason := NULL;
    IF NEW.profile_type = 'particulier' THEN
      IF NEW.statut_pro IS DISTINCT FROM 'na' AND NEW.statut_pro IS NOT NULL THEN
        NEW.statut_pro := 'na';
      END IF;
    ELSE
      NEW.statut_pro  := 'en_attente';
      NEW.is_validate := false;
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE : on ne garde que les transitions permises.
  IF NEW.plan_code IS DISTINCT FROM OLD.plan_code AND NEW.plan_code IS DISTINCT FROM 'free' THEN
    NEW.plan_code := OLD.plan_code;
  END IF;
  IF NEW.is_premium IS DISTINCT FROM OLD.is_premium AND NEW.is_premium THEN
    NEW.is_premium := OLD.is_premium;
  END IF;
  IF NEW.plan_until IS DISTINCT FROM OLD.plan_until AND NEW.plan_until IS NOT NULL THEN
    NEW.plan_until := OLD.plan_until;
  END IF;
  IF NEW.is_influencer IS DISTINCT FROM OLD.is_influencer THEN
    NEW.is_influencer := OLD.is_influencer;
  END IF;
  IF NEW.statut_pro IS DISTINCT FROM OLD.statut_pro
     AND NOT (NEW.statut_pro = 'en_attente' AND OLD.profile_type <> 'particulier')
     AND NOT (NEW.statut_pro = 'na' AND OLD.profile_type = 'particulier') THEN
    NEW.statut_pro := OLD.statut_pro;
  END IF;
  IF NEW.is_validate IS DISTINCT FROM OLD.is_validate
     AND NEW.is_validate AND OLD.profile_type <> 'particulier' THEN
    NEW.is_validate := OLD.is_validate;
  END IF;
  IF NEW.rejection_reason IS DISTINCT FROM OLD.rejection_reason AND NEW.rejection_reason IS NOT NULL THEN
    NEW.rejection_reason := OLD.rejection_reason;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_profiles_protege_colonnes ON public.user_profiles;
CREATE TRIGGER trg_user_profiles_protege_colonnes
  BEFORE INSERT OR UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.user_profiles_protege_colonnes();

-- users : la même porte pour les triggers système (drapeau pm.systeme).
CREATE OR REPLACE FUNCTION public.users_protect_sensitive_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- service_role (webhooks Stripe, routes API admin déjà en service_role)
  -- bypasse RLS mais pas les triggers — on le laisse passer explicitement
  -- pour ne rien casser côté flux déjà en production.
  IF current_setting('request.jwt.claim.role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;

  -- Triggers système (ex. essai gratuit) : drapeau posé localement.
  IF current_setting('pm.systeme', true) = 'on' THEN
    RETURN NEW;
  END IF;

  IF public.is_admin_uid(auth.jwt() ->> 'sub') THEN
    RETURN NEW;
  END IF;

  IF NEW.is_admin IS DISTINCT FROM OLD.is_admin
     OR NEW.is_dev IS DISTINCT FROM OLD.is_dev
     OR NEW.is_validate IS DISTINCT FROM OLD.is_validate
     OR NEW.verification_status IS DISTINCT FROM OLD.verification_status
     OR NEW.statut_pro IS DISTINCT FROM OLD.statut_pro
     OR NEW.plan_code IS DISTINCT FROM OLD.plan_code
     OR NEW.is_premium IS DISTINCT FROM OLD.is_premium
     OR NEW.valid_until IS DISTINCT FROM OLD.valid_until
     OR NEW.stripe_customer_id IS DISTINCT FROM OLD.stripe_customer_id
  THEN
    RAISE EXCEPTION 'Modification de champs réservés à l''administration refusée';
  END IF;

  RETURN NEW;
END;
$function$;

-- ── 2. Essai gratuit : droits système ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.grant_trial_on_new_pro_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_now TIMESTAMPTZ := now();
  v_plan_code TEXT;
BEGIN
  v_plan_code := CASE NEW.profile_type
    WHEN 'eleveur'          THEN 'premium'
    WHEN 'garde'            THEN 'premium'
    WHEN 'pension'          THEN 'premium'
    WHEN 'education'        THEN 'premium'
    WHEN 'toilettage'       THEN 'premium'
    WHEN 'sante'            THEN 'pro'
    WHEN 'marechal_ferrant' THEN 'pro'
    WHEN 'veterinaire'      THEN 'clinique'
    WHEN 'photographe'      THEN 'essentiel'
    ELSE NULL
  END;

  IF v_plan_code IS NULL THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM abonnements
    WHERE uid = NEW.uid AND profil_type = NEW.profile_type AND essai_gratuit = TRUE
  ) THEN
    RETURN NEW;
  END IF;

  BEGIN
    PERFORM set_config('pm.systeme', 'on', true);

    INSERT INTO abonnements (
      uid, profile_id, profil_type, plan_code, periodicite, statut,
      stripe_subscription_id, stripe_customer_id,
      date_debut, date_fin, essai_gratuit, created_at, updated_at
    ) VALUES (
      NEW.uid, NEW.id, NEW.profile_type, v_plan_code, 'mensuel', 'actif',
      NULL, NULL,
      v_now, v_now + INTERVAL '30 days', TRUE, v_now, v_now
    );

    UPDATE user_profiles
      SET essai_gratuit_utilise = TRUE,
          plan_code = v_plan_code, is_premium = TRUE, plan_until = v_now + INTERVAL '30 days'
      WHERE id = NEW.id;

    UPDATE users SET plan_code = v_plan_code, is_premium = TRUE WHERE uid = NEW.uid;

    PERFORM set_config('pm.systeme', 'off', true);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('pm.systeme', 'off', true);
    -- Ne doit jamais faire échouer la création du profil lui-même.
    RAISE WARNING 'essai gratuit non accordé (%): %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$function$;

-- ── 3. Policies ────────────────────────────────────────────────────────
DROP POLICY IF EXISTS user_profiles_all ON public.user_profiles;
DROP POLICY IF EXISTS user_profiles_anon_insert ON public.user_profiles;
DROP POLICY IF EXISTS user_profiles_anon_update ON public.user_profiles;
DROP POLICY IF EXISTS user_profiles_anon_select ON public.user_profiles;  -- doublon de public_read

DROP POLICY IF EXISTS user_profiles_owner_or_cogerant_update ON public.user_profiles;
DROP POLICY IF EXISTS user_profiles_update ON public.user_profiles;
CREATE POLICY user_profiles_update ON public.user_profiles
  FOR UPDATE TO anon, authenticated
  USING (
    (auth.jwt() ->> 'sub') = uid
    OR public.is_admin_uid(auth.jwt() ->> 'sub')
    OR EXISTS (
      SELECT 1 FROM public.elevage_cogerants c
      WHERE c.uid_gerant = user_profiles.uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
        AND (c.elevage_profile_id = user_profiles.id
             OR (c.elevage_profile_id IS NULL AND user_profiles.profile_type = 'eleveur'))
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = uid
    OR public.is_admin_uid(auth.jwt() ->> 'sub')
    OR EXISTS (
      SELECT 1 FROM public.elevage_cogerants c
      WHERE c.uid_gerant = user_profiles.uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
        AND (c.elevage_profile_id = user_profiles.id
             OR (c.elevage_profile_id IS NULL AND user_profiles.profile_type = 'eleveur'))
    )
  );

DROP POLICY IF EXISTS user_profiles_owner_delete ON public.user_profiles;
DROP POLICY IF EXISTS user_profiles_delete ON public.user_profiles;
CREATE POLICY user_profiles_delete ON public.user_profiles
  FOR DELETE TO anon, authenticated
  USING ((auth.jwt() ->> 'sub') = uid OR public.is_admin_uid(auth.jwt() ->> 'sub'));

-- user_profiles_owner_insert (uid = soi) et user_profiles_public_read
-- (lecture publique) sont conservées telles quelles.

COMMIT;
