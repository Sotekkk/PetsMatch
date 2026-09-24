-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 40/N + correctif urgent partage vétérinaire
--   education_progression, profile_members, influencer_requests,
--   contact_messages, factures_journal, partage_animal, partage_tokens,
--   pension_acces, vet_access_grants, vet_consultations, animal_acces_pro
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- ⚠️ CORRECTIF URGENT — régression trouvée en auditant cette vague :
-- le partage santé par lien/QR code pour un vétérinaire (vet_share_dialog.
-- dart + lib/pages/pro/vet_token_view.dart, table `partage_tokens`) ouvre
-- une page SANS CONNEXION (clé anon) qui lit directement vaccinations/
-- traitements/visites/vermifuges/antiparasitaires/allergies. Or la vague
-- 14/N (carnet_sante) a verrouillé ces tables à can_access_animal_health(),
-- qui exige un p_uid authentifié correspondant au propriétaire — cassant
-- de fait ce partage pour tout visiteur anonyme (vérifié en conditions
-- réelles : lecture vide sur vaccinations malgré un animal réel). Corrigé
-- en ajoutant à can_access_animal_health() une branche LECTURE SEULE : un
-- partage actif et non expiré existe pour cet animal (partage_tokens).
-- Même limite que pour les albums photo (vague 36/N) : la RLS ne peut pas
-- vérifier le token exact fourni, seulement qu'un partage actif existe.
--
-- education_progression : même schéma qu'ordonnances/comptes_rendus (vague
-- 33/N) — réutilise can_access_pro_document().
--
-- profile_members / vet_access_grants / vet_consultations / pension_acces /
-- animal_acces_pro : AUCUNE référence dans le code actuel (mécanismes
-- remplacés par `animal_access`, déjà sécurisée) mais contiennent des
-- données réelles résiduelles — verrouillées par sécurité.
--
-- influencer_requests : demandes soumises par un utilisateur (réseaux,
-- preuves) — privé au demandeur + admin.
--
-- contact_messages : formulaire de contact PUBLIC (aucune connexion
-- requise, website/src/app/contact/page.tsx) — écriture ouverte à
-- l'anonyme, lecture réservée à l'admin (jamais lue côté client sinon).
--
-- factures_journal : journal d'audit INALTÉRABLE des factures (numérotation
-- serveur, conformité) — jamais écrit par l'app elle-même (aucune
-- référence code), très probablement un trigger côté `factures`. Lecture
-- réservée au propriétaire de la facture concernée (uid_eleveur/cogérant)
-- + admin. Écriture ouverte à tout utilisateur connecté (le trigger
-- s'exécute dans le contexte de l'auteur de l'action sur `factures`) —
-- AUCUNE policy UPDATE/DELETE créée : un journal d'audit ne doit jamais
-- pouvoir être modifié ou supprimé via l'API, pas même par un admin.
--
-- partage_animal / partage_tokens : lecture publique nécessaire (validation
-- par token avant de connaître le contenu, comme album_partage) — écriture
-- réservée au partageur/propriétaire.
--
-- ⚠️ À TESTER après exécution :
--   1. Le lien de partage santé pour un vétérinaire (QR / lien 72h) affiche
--      de nouveau les vaccins/traitements/visites pour un visiteur non
--      connecté.
--   2. Le partage de fiche animal (lien /partage/[token]) fonctionne.
--   3. Le formulaire de contact du site fonctionne pour un visiteur non
--      connecté.
--   4. La facturation pro (créer une facture, avoir, PDF) continue de
--      fonctionner normalement.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── Correctif : can_access_animal_health() + branche partage vétérinaire ──
CREATE OR REPLACE FUNCTION public.can_access_animal_health(p_animal_id TEXT, p_uid TEXT, p_require_write BOOLEAN DEFAULT false)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM animaux a
    WHERE a.id = p_animal_id
      AND (
        a.uid_eleveur = p_uid OR a.uid_proprietaire = p_uid
        OR EXISTS (
          SELECT 1 FROM elevage_cogerants c
          WHERE c.uid_gerant = a.uid_eleveur
            AND c.uid_cogerant = p_uid AND c.statut = 'actif' AND c.date_fin IS NULL
        )
        OR EXISTS (
          SELECT 1 FROM employes e
          WHERE e.uid_eleveur = a.uid_eleveur
            AND e.uid_employe = p_uid
            AND e.actif = true
            AND (
              NOT p_require_write
              OR EXISTS (
                SELECT 1 FROM employe_permissions ep
                WHERE ep.eleveur_profile_id = e.eleveur_profile_id
                  AND ep.employe_profile_id = e.employe_profile_id
                  AND ep.permission = 'write_sante'
              )
            )
        )
        OR EXISTS (
          SELECT 1 FROM animaux_proprietes p
          WHERE p.animal_id = p_animal_id AND p.uid_proprio = p_uid AND p.date_fin IS NULL
        )
        OR (
          NOT p_require_write
          AND EXISTS (
            SELECT 1 FROM partage_tokens pt
            WHERE pt.animal_id = p_animal_id AND pt.expires_at > now()
          )
        )
      )
  );
$$;
GRANT EXECUTE ON FUNCTION public.can_access_animal_health(TEXT, TEXT, BOOLEAN) TO anon, authenticated;

-- ── education_progression (même schéma qu'ordonnances/comptes_rendus) ────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE education_progression ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'education_progression'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.education_progression', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "education_progression_select" ON education_progression
  FOR SELECT USING (
    public.can_access_pro_document(animal_id, owner_uid, NULL, pro_uid, NULL, (auth.jwt() ->> 'sub'))
  );
CREATE POLICY "education_progression_write" ON education_progression
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = education_progression.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = education_progression.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  );

-- ── influencer_requests (demandeur + admin) ───────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE influencer_requests ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'influencer_requests'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.influencer_requests', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "influencer_requests_select" ON influencer_requests
  FOR SELECT USING ((auth.jwt() ->> 'sub') = uid OR public.is_admin_uid((auth.jwt() ->> 'sub')));
CREATE POLICY "influencer_requests_insert" ON influencer_requests
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = uid);
CREATE POLICY "influencer_requests_update" ON influencer_requests
  FOR UPDATE USING (public.is_admin_uid((auth.jwt() ->> 'sub')))
  WITH CHECK (public.is_admin_uid((auth.jwt() ->> 'sub')));

-- ── contact_messages (formulaire public, lecture admin) ───────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE contact_messages ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'contact_messages'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.contact_messages', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "contact_messages_insert" ON contact_messages FOR INSERT WITH CHECK (true);
CREATE POLICY "contact_messages_select" ON contact_messages
  FOR SELECT USING (public.is_admin_uid((auth.jwt() ->> 'sub')));

-- ── factures_journal (audit inaltérable — jamais d'UPDATE/DELETE) ─────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE factures_journal ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'factures_journal'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.factures_journal', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "factures_journal_select" ON factures_journal
  FOR SELECT USING (
    public.is_admin_uid((auth.jwt() ->> 'sub'))
    OR EXISTS (
      SELECT 1 FROM factures f
      WHERE f.id::text = factures_journal.facture_id
        AND (
          f.uid_eleveur = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = f.uid_eleveur AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    )
  );
CREATE POLICY "factures_journal_insert" ON factures_journal
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') IS NOT NULL);

-- ── partage_animal (lecture publique nécessaire au flux token) ───────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE partage_animal ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'partage_animal'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.partage_animal', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "partage_animal_select" ON partage_animal FOR SELECT USING (true);
CREATE POLICY "partage_animal_insert" ON partage_animal
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = uid_partageur);
CREATE POLICY "partage_animal_update" ON partage_animal
  FOR UPDATE USING ((auth.jwt() ->> 'sub') = uid_partageur) WITH CHECK ((auth.jwt() ->> 'sub') = uid_partageur);
CREATE POLICY "partage_animal_delete" ON partage_animal
  FOR DELETE USING ((auth.jwt() ->> 'sub') = uid_partageur);

-- ── partage_tokens (lecture publique nécessaire au flux token vétérinaire) ─
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE partage_tokens ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'partage_tokens'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.partage_tokens', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "partage_tokens_select" ON partage_tokens FOR SELECT USING (true);
CREATE POLICY "partage_tokens_insert" ON partage_tokens
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = owner_id);
CREATE POLICY "partage_tokens_update" ON partage_tokens
  FOR UPDATE USING (true) WITH CHECK (true);
-- UPDATE ouverte à tous : le visiteur anonyme du lien doit pouvoir poser
-- used_at à sa première consultation (vet_token_view.dart) — même logique
-- que le token qui fait office d'authentification.
CREATE POLICY "partage_tokens_delete" ON partage_tokens
  FOR DELETE USING ((auth.jwt() ->> 'sub') = owner_id);

-- ── profile_members / vet_access_grants / vet_consultations / pension_acces
--    / animal_acces_pro : aucune référence code actuelle, verrouillées ──────
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['pension_acces','animal_acces_pro']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;
    EXECUTE format($f$
      CREATE POLICY "%1$s_parties" ON public.%1$I
        FOR ALL USING (
          (auth.jwt() ->> 'sub') = pro_uid OR (auth.jwt() ->> 'sub') = owner_uid
        )
        WITH CHECK (
          (auth.jwt() ->> 'sub') = pro_uid OR (auth.jwt() ->> 'sub') = owner_uid
        )
    $f$, t);
  END LOOP;
END $$;

-- vet_access_grants utilise vet_id/owner_id (pas pro_uid/owner_uid) et
-- vet_consultations n'a pas de propriétaire du tout — traités séparément.
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'vet_access_grants'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.vet_access_grants', pol.policyname);
  END LOOP;
  EXECUTE $p$
    CREATE POLICY "vet_access_grants_parties" ON vet_access_grants
      FOR ALL USING ((auth.jwt() ->> 'sub') = vet_id OR (auth.jwt() ->> 'sub') = owner_id)
      WITH CHECK ((auth.jwt() ->> 'sub') = vet_id OR (auth.jwt() ->> 'sub') = owner_id)
  $p$;
END $$;

DO $$
DECLARE pol RECORD;
BEGIN
  IF to_regclass('public.vet_consultations') IS NULL THEN RETURN; END IF;
  ALTER TABLE vet_consultations ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'vet_consultations'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.vet_consultations', pol.policyname);
  END LOOP;
  EXECUTE $p$
    CREATE POLICY "vet_consultations_vet_or_owner" ON vet_consultations
      FOR ALL USING (
        (auth.jwt() ->> 'sub') = vet_id
        OR public.is_animal_owner_or_related(vet_consultations.animal_id, (auth.jwt() ->> 'sub'))
      )
      WITH CHECK ((auth.jwt() ->> 'sub') = vet_id)
  $p$;
END $$;

DO $$
DECLARE pol RECORD;
BEGIN
  IF to_regclass('public.profile_members') IS NULL THEN RETURN; END IF;
  ALTER TABLE profile_members ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'profile_members'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.profile_members', pol.policyname);
  END LOOP;
  EXECUTE $p$
    CREATE POLICY "profile_members_parties" ON profile_members
      FOR ALL USING (
        EXISTS (SELECT 1 FROM user_profiles up WHERE up.id = profile_members.org_profile_id AND up.uid = (auth.jwt() ->> 'sub'))
        OR EXISTS (SELECT 1 FROM user_profiles up WHERE up.id = profile_members.member_profile_id AND up.uid = (auth.jwt() ->> 'sub'))
      )
      WITH CHECK (
        EXISTS (SELECT 1 FROM user_profiles up WHERE up.id = profile_members.org_profile_id AND up.uid = (auth.jwt() ->> 'sub'))
      )
  $p$;
END $$;

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN (
  'education_progression','influencer_requests','contact_messages','factures_journal',
  'partage_animal','partage_tokens','profile_members','vet_access_grants',
  'vet_consultations','pension_acces','animal_acces_pro'
)
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN (
--       'education_progression','influencer_requests','contact_messages','factures_journal',
--       'partage_animal','partage_tokens','profile_members','vet_access_grants',
--       'vet_consultations','pension_acces','animal_acces_pro'
--     )
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- ALTER TABLE education_progression DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE influencer_requests DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE contact_messages DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE factures_journal DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE partage_animal DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE partage_tokens DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE profile_members DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE vet_access_grants DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE vet_consultations DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE pension_acces DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE animal_acces_pro DISABLE ROW LEVEL SECURITY;
