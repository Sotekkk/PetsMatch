-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 33/N : credit_wallets, credit_transactions,
--   ordonnances, comptes_rendus, transferts_propriete
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- credit_wallets / credit_transactions : l'écriture était déjà verrouillée
-- (migration_credits_secure.sql, RPC credit_spend/credit_grant SECURITY
-- DEFINER) mais la LECTURE était volontairement restée ouverte
-- (USING(true), commentaire "l'appli lit le solde directement") — en
-- pratique, tout le code ne lit jamais que .eq('uid', soi-même)
-- (chatScreen.dart, abonnements_achats_page.dart, social_feed_page.dart) :
-- aucun besoin réel de voir le solde/l'historique d'un AUTRE utilisateur.
-- Resserré à self. Les RPC (SECURITY DEFINER) restent inchangées, elles
-- contournent la RLS de toute façon.
--
-- ordonnances / comptes_rendus (documents pro liés à un animal, PDF/notes
-- médicales) : jamais protégés jusqu'ici. animal_id résout la propriété de
-- l'animal (co-propriétaires inclus, cf. mémoire "RLS liée à un animal"),
-- MAIS ces tables acceptent aussi un animal_id "placeholder" de portée
-- (ex: "portee_..._1") qui ne correspond à AUCUNE ligne `animaux` tant que
-- le chiot n'est pas enregistré individuellement — dans ce cas, owner_uid/
-- owner_profile_id (capturés à l'écriture par le pro) sont le SEUL moyen de
-- donner accès au propriétaire réel. D'où : accès accordé si
-- is_animal_owner_or_related(animal_id) RÉUSSIT (résolution dynamique,
-- couvre les co-propriétaires ajoutés après coup) OU, à défaut (portée non
-- enregistrée), owner_uid/owner_profile_id correspond. Écriture réservée au
-- pro qui a créé le document (pro_uid/cogérant) — jamais au propriétaire,
-- qui ne fait que consulter dans le code actuel.
--
-- transferts_propriete : AUCUNE référence dans le code actuel (ni app ni
-- site) — probablement un ancien flux remplacé par `cessions`. Verrouillé
-- par sécurité au vendeur/acheteur, sans impact fonctionnel connu.
--
-- ⚠️ À TESTER après exécution :
--   1. La page Abonnements & Achats (solde crédits, historique, packs)
--      continue de s'afficher normalement pour son propriétaire.
--   2. Les ordonnances/comptes rendus déposés par un pro restent visibles
--      pour lui ET pour le propriétaire de l'animal concerné (y compris un
--      co-propriétaire), et pour une portée non encore enregistrée
--      individuellement.
--   3. Déposer une nouvelle ordonnance/compte rendu fonctionne toujours
--      pour le pro (et un cogérant actif de son profil).
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── credit_wallets / credit_transactions : lecture resserrée à self ───────
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['credit_wallets','credit_transactions']
  LOOP
    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;
    EXECUTE format($f$ CREATE POLICY "%1$s_select_self" ON public.%1$I FOR SELECT USING ((auth.jwt() ->> 'sub') = uid) $f$, t);
  END LOOP;
END $$;
-- Note : aucune policy INSERT/UPDATE/DELETE recréée — l'écriture directe
-- reste impossible pour anon/authenticated (REVOKE déjà en place depuis
-- migration_credits_secure.sql), tout passe par credit_spend/credit_grant.

-- ── Fonction : accès à un document pro lié à un animal (ordo / CR) ─────────
CREATE OR REPLACE FUNCTION public.can_access_pro_document(
  p_animal_id        TEXT,
  p_owner_uid        TEXT,
  p_owner_profile_id UUID,
  p_pro_uid          TEXT,
  p_pro_profile_id   UUID,
  p_uid              TEXT
)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT p_uid IS NOT NULL AND (
    p_pro_uid = p_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = p_pro_uid AND c.uid_cogerant = p_uid AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR (p_animal_id IS NOT NULL AND public.is_animal_owner_or_related(p_animal_id, p_uid))
    OR p_owner_uid = p_uid
    OR (p_owner_profile_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM user_profiles up WHERE up.id = p_owner_profile_id AND up.uid = p_uid
    ))
  );
$$;
GRANT EXECUTE ON FUNCTION public.can_access_pro_document(TEXT, TEXT, UUID, TEXT, UUID, TEXT) TO anon, authenticated;

-- ── ordonnances ─────────────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE ordonnances ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'ordonnances'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.ordonnances', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "ordonnances_select" ON ordonnances
  FOR SELECT USING (
    public.can_access_pro_document(animal_id, owner_uid, owner_profile_id, pro_uid, pro_profile_id, (auth.jwt() ->> 'sub'))
  );
CREATE POLICY "ordonnances_write" ON ordonnances
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = ordonnances.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = ordonnances.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  );

-- ── comptes_rendus ──────────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE comptes_rendus ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'comptes_rendus'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.comptes_rendus', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "comptes_rendus_select" ON comptes_rendus
  FOR SELECT USING (
    public.can_access_pro_document(animal_id, owner_uid, owner_profile_id, pro_uid, pro_profile_id, (auth.jwt() ->> 'sub'))
  );
CREATE POLICY "comptes_rendus_write" ON comptes_rendus
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = comptes_rendus.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = comptes_rendus.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  );

-- ── transferts_propriete (aucune référence code actuelle, verrouillé par sécurité) ──
DO $$
DECLARE pol RECORD;
BEGIN
  IF to_regclass('public.transferts_propriete') IS NULL THEN RETURN; END IF;
  ALTER TABLE transferts_propriete ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'transferts_propriete'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.transferts_propriete', pol.policyname);
  END LOOP;
  EXECUTE $p$
    CREATE POLICY "transferts_propriete_parties" ON transferts_propriete
      FOR ALL USING (
        (auth.jwt() ->> 'sub') = uid_vendeur OR (auth.jwt() ->> 'sub') = uid_acheteur
      )
      WITH CHECK (
        (auth.jwt() ->> 'sub') = uid_vendeur OR (auth.jwt() ->> 'sub') = uid_acheteur
      )
  $p$;
END $$;

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('credit_wallets','credit_transactions','ordonnances','comptes_rendus','transferts_propriete')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('credit_wallets','credit_transactions','ordonnances','comptes_rendus','transferts_propriete')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- CREATE POLICY "wallets_select"      ON credit_wallets      FOR SELECT USING (true);
-- CREATE POLICY "transactions_select" ON credit_transactions FOR SELECT USING (true);
-- ALTER TABLE ordonnances DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE comptes_rendus DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE transferts_propriete DISABLE ROW LEVEL SECURITY;
