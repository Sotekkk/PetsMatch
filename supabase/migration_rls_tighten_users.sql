-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 13/N : users
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- `users` est la table d'identité de connexion (uid, email, nom, tél,
-- adresse, statut pro/élevage...) — la table la plus sensible RGPD du
-- projet, jamais touchée jusqu'ici (entièrement ouverte en lecture ET
-- écriture à quiconque). Point de départ de toute cette démarche RLS.
--
-- Modèle retenu :
--   SELECT  : reste public (comme user_profiles, vague 1/N) — de
--             nombreux flux légitimes cherchent UN AUTRE utilisateur par
--             email/uid (cession, cogérance, contrat, invitation employé,
--             recherche pension par puce...), aucune régression de ce
--             côté : ces infos sont déjà largement exposées via
--             user_profiles.
--   INSERT  : uniquement sa propre ligne (création de compte).
--   UPDATE  : soi-même OU un admin (public.is_admin_uid, fonction
--             SECURITY DEFINER — nécessaire pour éviter l'auto-référence :
--             une policy UPDATE sur `users` qui interroge `users.is_admin`
--             directement provoquerait la même récursion RLS que les
--             incidents animaux_proprietes/animal_access de ce chantier).
--   DELETE  : uniquement sa propre ligne (suppression de compte,
--             profil/page.tsx:2728).
--
-- ⚠️ POINT SUPPLÉMENTAIRE PAR RAPPORT AUX VAGUES PRÉCÉDENTES :
-- `users` porte aussi des colonnes sensibles sur la MÊME ligne que
-- l'utilisateur peut modifier lui-même : is_admin, is_dev, is_validate,
-- verification_status, statut_pro, plan_code, is_premium, valid_until,
-- stripe_customer_id. RLS étant ligne par ligne (pas colonne par colonne),
-- une simple policy « le propriétaire peut UPDATE sa ligne » laisserait
-- n'importe quel utilisateur s'auto-attribuer is_admin=true via un appel
-- REST direct. Un TRIGGER (les policies RLS ne peuvent pas faire de
-- contrôle par colonne) bloque donc la modification de ces colonnes
-- précises sauf par un admin ou par le service_role (webhooks Stripe,
-- routes API admin déjà en service_role — non affectées).
--
-- ⚠️ À TESTER après exécution :
--   1. Connexion / inscription fonctionnent toujours (lecture + création
--      de la ligne `users`).
--   2. Modifier son propre profil (nom, téléphone, adresse...) fonctionne
--      toujours, app + site.
--   3. Rechercher un utilisateur par email/nom pour une cession, une
--      cogérance, un contrat, une invitation employé fonctionne toujours.
--   4. Un admin peut toujours valider/rejeter un compte pro
--      (verification_detail.dart, pro_detail.dart /admin).
--   5. Un utilisateur NON admin ne peut PAS s'auto-attribuer is_admin,
--      is_premium, etc. (tester une requête directe si possible — doit
--      échouer avec « Modification de champs réservés... »).
--   6. Suppression de compte (Paramètres > Supprimer mon compte)
--      fonctionne toujours.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- Admin du uid donné — SECURITY DEFINER pour ne pas re-déclencher la RLS
-- de `users` depuis sa propre policy (auto-référence = récursion infinie).
CREATE OR REPLACE FUNCTION public.is_admin_uid(p_uid TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT COALESCE((SELECT is_admin FROM public.users WHERE uid = p_uid), false);
$$;
GRANT EXECUTE ON FUNCTION public.is_admin_uid(TEXT) TO anon, authenticated;

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Supprime TOUTE policy existante sur `users`, quel que soit son nom —
-- un DROP POLICY IF EXISTS par nom deviné (comme dans les vagues
-- précédentes) a laissé passer ici une policy permissive au nom inconnu :
-- Postgres combine les policies d'une même commande en OR, donc une seule
-- policy `USING(true)` oubliée suffit à rendre la nouvelle policy
-- restrictive inutile. Repli générique et sûr pour cette table.
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'users'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.users', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "users_select_all" ON users
  FOR SELECT USING (true);

CREATE POLICY "users_insert_own" ON users
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = uid);

CREATE POLICY "users_update_own_or_admin" ON users
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );

CREATE POLICY "users_delete_own" ON users
  FOR DELETE USING ((auth.jwt() ->> 'sub') = uid);

-- ── Verrou colonnes sensibles (trigger, complète la RLS ci-dessus) ────────
CREATE OR REPLACE FUNCTION public.users_protect_sensitive_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- service_role (webhooks Stripe, routes API admin déjà en service_role)
  -- bypasse RLS mais pas les triggers — on le laisse passer explicitement
  -- pour ne rien casser côté flux déjà en production.
  IF current_setting('request.jwt.claim.role', true) = 'service_role' THEN
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
$$;

DROP TRIGGER IF EXISTS trg_users_protect_sensitive ON users;
CREATE TRIGGER trg_users_protect_sensitive
  BEFORE UPDATE ON users
  FOR EACH ROW
  EXECUTE FUNCTION public.users_protect_sensitive_fields();

-- Vérification
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'users'
ORDER BY cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP TRIGGER IF EXISTS trg_users_protect_sensitive ON users;
-- DROP FUNCTION IF EXISTS public.users_protect_sensitive_fields();
-- DROP POLICY IF EXISTS "users_select_all" ON users;
-- DROP POLICY IF EXISTS "users_insert_own" ON users;
-- DROP POLICY IF EXISTS "users_update_own_or_admin" ON users;
-- DROP POLICY IF EXISTS "users_delete_own" ON users;
-- ALTER TABLE users DISABLE ROW LEVEL SECURITY;
-- DROP FUNCTION IF EXISTS public.is_admin_uid(TEXT);
