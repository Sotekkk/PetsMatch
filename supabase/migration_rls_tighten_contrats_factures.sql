-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 15/N : contrats, factures
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- `contrats` : bibliothèque de documents de l'éleveur (uid_eleveur direct,
-- pas d'accès externe/anonyme identifié dans le code actuel) — verrouillage
-- complet, même modèle que les vagues précédentes.
--
-- `factures` : SELECT laissé en l'état (USING(true)) — chaque facture porte
-- un `token` unique utilisé par /facture/[token] pour qu'un client SANS
-- compte PetsMatch consulte sa facture par lien (comme documents_animaux,
-- déjà identifié « à traiter séparément » : une policy RLS ne peut pas
-- vérifier qu'un visiteur a fourni le bon token, seulement que la ligne EN
-- A un — la verrouiller casserait ce flux ou l'ouvrirait en bloc selon le
-- sens choisi). En revanche l'ÉCRITURE (INSERT/UPDATE), jusqu'ici ouverte à
-- quiconque, n'a aucune raison de rester publique : verrouillée ici.
-- Aucune policy DELETE créée : une facture émise est inaltérable (règle
-- déjà en place, migration_facturation_phase3.sql, art. 286-I-3° bis CGI)
-- et le code ne supprime jamais de facture — DELETE reste donc refusé pour
-- tout le monde une fois RLS activée, ce qui est le comportement voulu.
--
-- ⚠️ Périmètre volontairement limité : devis, cessions,
-- certificats_engagement, contract_signers, contract_audit et
-- documents_animaux partagent tous ce même modèle « lien à token pour un
-- acquéreur/client sans compte » — laissés pour une vague dédiée, le temps
-- de concevoir le bon mécanisme (RPC SECURITY DEFINER côté token plutôt
-- que RLS directe).
--
-- ⚠️ À TESTER après exécution :
--   1. "Mes contrats" (bibliothèque de documents éleveur, si utilisée)
--      s'affiche normalement.
--   2. La facturation (créer une facture, changer son statut) fonctionne
--      toujours pour l'éleveur et un cogérant actif.
--   3. Le lien /facture/[token] envoyé à un client (sans compte) affiche
--      toujours la facture normalement — ne doit RIEN changer ici.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── contrats ─────────────────────────────────────────────────────────────
ALTER TABLE contrats ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'contrats'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.contrats', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "contrats_owner_or_cogerant" ON contrats
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = contrats.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = contrats.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- ── factures (écriture uniquement — lecture laissée ouverte, cf. en-tête) ──
ALTER TABLE factures ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'factures'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.factures', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "factures_select_all" ON factures
  FOR SELECT USING (true);

CREATE POLICY "factures_owner_or_cogerant_insert" ON factures
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = factures.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "factures_owner_or_cogerant_update" ON factures
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = factures.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = factures.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );
-- Pas de policy DELETE : voir note en-tête (inaltérabilité légale).

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('contrats','factures')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('contrats','factures')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- ALTER TABLE contrats DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE factures DISABLE ROW LEVEL SECURITY;
