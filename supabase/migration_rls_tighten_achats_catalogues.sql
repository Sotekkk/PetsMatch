-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 39/N : achats_ponctuels, produits_ponctuels,
--   marques_aliments, species_object_tiers, user_cosmetics, virtual_gifts
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- achats_ponctuels (boosts d'annonce achetés via Stripe) : lecture privée à
-- son acheteur (mes_achats_page.dart / mes-achats/page.tsx, toujours
-- .eq('uid', soi-même)) — écriture exclusivement via le webhook Stripe
-- (clé service_role, api/stripe/webhook/route.ts), aucune écriture client.
--
-- produits_ponctuels / marques_aliments / species_object_tiers : catalogues
-- de référence, lecture publique, jamais écrits côté client (toujours via
-- l'admin/service_role ou un jeu de données statique) — verrouillés en
-- écriture par sécurité.
--
-- user_cosmetics : l'anneau d'avatar équipé (active_value/active_by_profile)
-- est affiché publiquement pour N'IMPORTE QUEL auteur dans le fil Pets
-- Social (social_feed_page.dart, lecture croisée sur tous les profils
-- affichés) — lecture publique conservée, écriture réservée à son
-- propriétaire (uid).
--
-- virtual_gifts (cadeaux virtuels sur un post) : AUCUNE référence dans le
-- code actuel — verrouillé par sécurité (expéditeur/destinataire), sans
-- impact fonctionnel connu.
--
-- ⚠️ À TESTER après exécution :
--   1. « Mes achats » (boosts d'annonce) reste visible pour son acheteur.
--   2. Les tarifs de boost, marques d'aliments (calcul de ration) et
--      paliers de progression restent visibles.
--   3. L'anneau d'avatar équipé reste visible sur tous les posts du fil
--      Pets Social ; le changer fonctionne pour son propriétaire.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── achats_ponctuels (privé à l'acheteur, écriture webhook uniquement) ────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE achats_ponctuels ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'achats_ponctuels'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.achats_ponctuels', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "achats_ponctuels_select" ON achats_ponctuels
  FOR SELECT USING ((auth.jwt() ->> 'sub') = uid);
-- Pas de policy INSERT/UPDATE/DELETE : seul service_role écrit (webhook Stripe).

-- ── Catalogues publics, écriture jamais côté client ────────────────────────
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['produits_ponctuels','marques_aliments','species_object_tiers']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;
    EXECUTE format($f$ CREATE POLICY "%1$s_select" ON public.%1$I FOR SELECT USING (true) $f$, t);
  END LOOP;
END $$;

-- ── user_cosmetics (affiché publiquement dans le fil, écriture self) ──────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE user_cosmetics ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'user_cosmetics'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.user_cosmetics', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "user_cosmetics_select" ON user_cosmetics FOR SELECT USING (true);
CREATE POLICY "user_cosmetics_write" ON user_cosmetics
  FOR ALL USING ((auth.jwt() ->> 'sub') = uid) WITH CHECK ((auth.jwt() ->> 'sub') = uid);

-- ── virtual_gifts (aucune référence code actuelle) ─────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  IF to_regclass('public.virtual_gifts') IS NULL THEN RETURN; END IF;
  ALTER TABLE virtual_gifts ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'virtual_gifts'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.virtual_gifts', pol.policyname);
  END LOOP;
  EXECUTE $p$
    CREATE POLICY "virtual_gifts_parties" ON virtual_gifts
      FOR ALL USING (
        (auth.jwt() ->> 'sub') = sender_uid OR (auth.jwt() ->> 'sub') = receiver_uid
      )
      WITH CHECK ((auth.jwt() ->> 'sub') = sender_uid)
  $p$;
END $$;

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('achats_ponctuels','produits_ponctuels','marques_aliments','species_object_tiers','user_cosmetics','virtual_gifts')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('achats_ponctuels','produits_ponctuels','marques_aliments','species_object_tiers','user_cosmetics','virtual_gifts')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- ALTER TABLE achats_ponctuels DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE produits_ponctuels DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE marques_aliments DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE species_object_tiers DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE user_cosmetics DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE virtual_gifts DISABLE ROW LEVEL SECURITY;
