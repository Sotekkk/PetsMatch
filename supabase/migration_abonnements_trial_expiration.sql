-- ═══════════════════════════════════════════════════════════════════════════
-- Essai gratuit 30j (nouveaux profils pro, tous métiers dotés d'une grille de
-- plans) + colonnes support pour l'expiration/relance des abonnements gérée
-- côté Cloud Function (functions/abonnements.js).
--
-- Pourquoi : aucun essai gratuit n'existait réellement (onboardingHasTrial()
-- n'affichait qu'un texte, sans jamais créer de ligne `abonnements` ni de
-- garde anti-abus). Idempotent, à exécuter dans le SQL Editor Supabase.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Colonnes -----------------------------------------------------------
ALTER TABLE abonnements ADD COLUMN IF NOT EXISTS essai_gratuit BOOLEAN DEFAULT false;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS essai_gratuit_utilise BOOLEAN DEFAULT false;
-- (annonces.statut est une colonne TEXT libre, sans contrainte CHECK — le
-- statut 'quota_depasse' introduit par functions/abonnements.js s'utilise
-- directement, aucune migration de schéma nécessaire côté annonces.)

-- 2. Trigger : octroi de l'essai gratuit à la création d'un profil pro --
-- Un seul essai par (uid, profile_type) — la garde anti-abus s'appuie sur
-- l'historique `abonnements` (essai_gratuit=true), pas sur le seul flag
-- `user_profiles.essai_gratuit_utilise` : ce dernier est purement dénormalisé
-- pour l'affichage UI, et ne doit jamais être la seule source de vérité, car
-- un profil peut être supprimé puis recréé (ProfileService.deleteProfile)
-- sans que la ligne `abonnements` correspondante ne disparaisse.
--
-- Profils exclus (pas de grille de plans / pas de notion payante) :
--   particulier, association (cf. onboardingHasTrial(), déjà gratuits par
--   design) ; taxi_animalier, restauration (aucune page /abonnement, aucune
--   grille de plans définie à ce jour — rien à essayer).
CREATE OR REPLACE FUNCTION grant_trial_on_new_pro_profile()
RETURNS trigger AS $$
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
  EXCEPTION WHEN OTHERS THEN
    -- Ne doit jamais faire échouer la création du profil lui-même.
    NULL;
  END;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_grant_trial_on_new_pro_profile ON user_profiles;
CREATE TRIGGER trg_grant_trial_on_new_pro_profile
  AFTER INSERT ON user_profiles
  FOR EACH ROW EXECUTE FUNCTION grant_trial_on_new_pro_profile();

-- Vérif :
--   INSERT INTO user_profiles(uid, profile_type, ...) VALUES ('<test-uid>', 'garde', ...);
--   SELECT plan_code, essai_gratuit, date_fin - date_debut AS duree
--     FROM abonnements WHERE uid = '<test-uid>' AND essai_gratuit = true;
--   -- attendu : plan_code='premium', essai_gratuit=true, duree='30 days'
