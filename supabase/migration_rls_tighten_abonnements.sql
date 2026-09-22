-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 9/N : abonnements, achats_ponctuels
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase). Aucune self-référence ni dépendance croisée
-- (leçon des vagues 5 et 6) : uniquement une référence vers
-- elevage_cogerants.
--
-- Contexte : ces deux tables étaient déjà en lecture permissive
-- (USING(true), migration_abonnements_rls_fix.sql) et SANS AUCUNE policy
-- d'écriture pour anon/authenticated — les écritures (Stripe webhook,
-- routes admin) passent déjà exclusivement par la clé service_role, qui
-- contourne RLS. Cette vague ne change donc QUE la lecture : plus de
-- lecture publique de "qui a quel abonnement", réservée au titulaire et à
-- un cogérant actif — les écritures restent identiques (toujours
-- exclusivement service_role, aucune policy ajoutée ici).
--
-- ⚠️ À TESTER après exécution :
--   1. La page Abonnement / mon plan actuel s'affiche normalement (app +
--      site), pour un compte particulier, éleveur, et un pro (véto,
--      pension, garde, éducation...).
--   2. Un cogérant actif voit le plan payant réel de l'élevage qu'il
--      co-gère (pas "Découverte").
--   3. Un achat ponctuel (ex. annonce supplémentaire) reste visible après
--      paiement.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.abonnements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "abonnements_read" ON public.abonnements;
DROP POLICY IF EXISTS "abonnements_owner_or_cogerant_select" ON public.abonnements;

CREATE POLICY "abonnements_owner_or_cogerant_select" ON public.abonnements
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = abonnements.uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

ALTER TABLE public.achats_ponctuels ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "achats_ponctuels_read" ON public.achats_ponctuels;
DROP POLICY IF EXISTS "achats_ponctuels_owner_or_cogerant_select" ON public.achats_ponctuels;

CREATE POLICY "achats_ponctuels_owner_or_cogerant_select" ON public.achats_ponctuels
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = achats_ponctuels.uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- Vérification
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename IN ('abonnements','achats_ponctuels')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "abonnements_owner_or_cogerant_select" ON public.abonnements;
-- CREATE POLICY "abonnements_read" ON public.abonnements FOR SELECT USING (true);
--
-- DROP POLICY IF EXISTS "achats_ponctuels_owner_or_cogerant_select" ON public.achats_ponctuels;
-- CREATE POLICY "achats_ponctuels_read" ON public.achats_ponctuels FOR SELECT USING (true);
