-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 22/N : certificats_engagement
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- Comme factures/pension_factures/partage_suivi_education (vagues
-- 15/18/19) : chaque certificat porte un token_signature utilisé par
-- /certificat/[token] pour qu'un acquéreur SANS compte le consulte par
-- lien — lecture laissée ouverte. Vérifié : cette page web ne fait QUE
-- lire ; la signature passe par api/certificat/sign/route.ts, qui utilise
-- déjà SUPABASE_SERVICE_ROLE_KEY (contourne la RLS, non affecté par ce
-- verrouillage).
--
-- Cas différent, à couvrir explicitement : dans l'appli, un acquéreur
-- QUI A un compte PetsMatch signe directement depuis
-- contrat_signature_page.dart (mode certificatEngagementToken) — un vrai
-- utilisateur Firebase authentifié, donc acquereur_uid = son propre uid.
-- Écriture donc ouverte au cédant/cogérant ET à l'acquéreur (sur sa
-- propre ligne) pour cette raison précise.
--
-- devis et cessions PARTAGENT le même système de token mais leur
-- acceptation/signature passe par un appel direct non-authentifié depuis
-- le navigateur (supabase.from(...).update(...) dans devis/[token] et
-- signer-cession/[token], PAS par une route API service_role) — verrouiller
-- l'écriture casserait ces flux. Laissés en l'état pour une vague dédiée
-- (migration de ces deux flux vers une route API/RPC, comme déjà fait pour
-- certificats_engagement, avant de pouvoir verrouiller sans casser).
--
-- ⚠️ À TESTER après exécution :
--   1. La liste des certificats d'engagement (Élevage → Admin) s'affiche
--      normalement pour le cédant et un cogérant actif.
--   2. Envoyer un nouveau certificat fonctionne toujours.
--   3. Le lien /certificat/[token] envoyé à un acquéreur sans compte
--      continue de fonctionner (lecture + signature via l'API).
--   4. Un acquéreur AVEC un compte PetsMatch peut toujours signer depuis
--      l'appli (fiche animal particulier → certificat en attente).
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

ALTER TABLE certificats_engagement ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'certificats_engagement'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.certificats_engagement', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "certificats_engagement_select_all" ON certificats_engagement
  FOR SELECT USING (true);

CREATE POLICY "certificats_engagement_insert" ON certificats_engagement
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = cedant_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = certificats_engagement.cedant_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "certificats_engagement_update" ON certificats_engagement
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = cedant_uid
    OR (auth.jwt() ->> 'sub') = acquereur_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = certificats_engagement.cedant_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = cedant_uid
    OR (auth.jwt() ->> 'sub') = acquereur_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = certificats_engagement.cedant_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "certificats_engagement_delete" ON certificats_engagement
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = cedant_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = certificats_engagement.cedant_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename = 'certificats_engagement'
ORDER BY cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "certificats_engagement_select_all" ON certificats_engagement;
-- DROP POLICY IF EXISTS "certificats_engagement_insert" ON certificats_engagement;
-- DROP POLICY IF EXISTS "certificats_engagement_update" ON certificats_engagement;
-- DROP POLICY IF EXISTS "certificats_engagement_delete" ON certificats_engagement;
-- CREATE POLICY "cedant_all" ON certificats_engagement FOR ALL USING (true) WITH CHECK (true);
