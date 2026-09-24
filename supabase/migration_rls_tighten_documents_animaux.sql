-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 44/N : documents_animaux, contract_signers,
--   contract_audit (moteur générique de contrats /signer-contrat/[token])
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- ⚠️ Point important, propre à cette table : contrairement au site
-- (désormais entièrement via routes API), l'appli Flutter
-- (lib/pages/contrats/contrat_signature_page.dart) écrit ENCORE en direct
-- dans documents_animaux, y compris pour un acquéreur authentifié (pas
-- l'éleveur) qui signe depuis l'appli après avoir reçu une notification —
-- documents_animaux n'a pas de colonne uid_acquereur dédiée (contrairement
-- à certificats_engagement/cessions), seulement metadata.acquereur_email.
-- La policy d'écriture ajoute donc une branche : un compte authentifié dont
-- l'email correspond à metadata.acquereur_email du document. Même modèle de
-- confiance que le site (saveFemelle vérifiait déjà user.email ===
-- metadata.acquereur_email) — pas une régression, une continuité.
--
-- documents_animaux était volontairement grand ouvert (USING(true) partout,
-- migration_documents_animaux.sql) car /signer-contrat/[token] écrivait en
-- direct depuis un visiteur anonyme (signature, refus, sélection femelle,
-- correction coordonnées). Corrigé AVANT cette migration en déplaçant TOUTE
-- l'écriture anonyme vers des routes API dédiées (service_role) :
--   - api/contracts/[id]/sign     (signature éleveur/acquéreur — porte la
--     logique complète : transfert de propriété, registre, notifications,
--     acceptation devis éducation — portée telle quelle depuis la page)
--   - api/contracts/[id]/refuse   (déjà une route API, corrigée pour
--     utiliser service_role + absorber le refus du devis lié)
--   - api/contracts/[id]/cancel   (déjà une route API, corrigée pour
--     utiliser service_role + AJOUT d'une vérification d'autorisation —
--     absente jusqu'ici : n'importe qui connaissant l'id pouvait annuler)
--   - api/contracts/[id]/femelle  (nouvelle — sélection femelle, saillie)
--   - api/contracts/[id]/contact  (nouvelle — correction coordonnées acquéreur)
-- La RLS peut donc être verrouillée à l'éleveur/cogérant : ces routes
-- passent par service_role, qui contourne la RLS de toute façon. Lecture
-- publique conservée (token flow + nombreuses lectures authentifiées
-- particulier/pro à travers l'appli et le site).
--
-- contract_signers / contract_audit (PREP02/PREP03) avaient déjà une RLS,
-- mais avec le même bug que `users` vague 13/N : `auth.uid()` (natif
-- Supabase) au lieu de `auth.jwt() ->> 'sub'` — TOUJOURS NULL pour un
-- compte Firebase. Conséquences concrètes :
--   - contract_audit : lecture jamais possible pour l'éleveur (policy
--     toujours fausse) — corrigé.
--   - contract_signers : lecture/écriture de facto ouvertes à N'IMPORTE QUI
--     via la branche `d.token IS NOT NULL` (vrai pour presque tous les
--     documents) combinée à un `auth.uid()` toujours faux côté check —
--     un visiteur anonyme pouvait modifier n'importe quelle ligne
--     contract_signers de n'importe quel contrat. Table confirmée SANS
--     AUCUN usage dans le flux live actuel (ContractService/
--     CanvasSignatureProvider ne sont appelés que par les routes
--     cancel/audit, jamais .create()/.sendForSignature()) — corrigé sans
--     risque fonctionnel : écriture réservée éleveur/cogérant, lecture
--     publique conservée (cohérent avec l'intention d'origine : lecture
--     via token pour une future intégration YouSign).
--
-- ⚠️ À TESTER après exécution :
--   1. Un client peut toujours signer un contrat (tout type : vente,
--      réservation, garde, pension, toilettage, photographe, éducation,
--      santé, adoption, saillie) depuis /signer-contrat/[token] — signature
--      éleveur ET acquéreur.
--   2. Signer un contrat de vente/certificat de cession transfère bien
--      l'animal (registre, historique de propriété) quand l'éleveur pose
--      la dernière signature.
--   3. Refuser, annuler un contrat fonctionnent toujours.
--   4. Sélectionner la femelle (contrat saillie) et corriger ses
--      coordonnées (acquéreur) fonctionnent toujours.
--   5. L'éleveur/pro peut créer, modifier, supprimer ses contrats depuis
--      son tableau de bord (elevage/pension/garde/toilettage/photographe/
--      education/association/marechal-ferrant/sante).
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── documents_animaux ──────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE documents_animaux ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'documents_animaux'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.documents_animaux', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "documents_animaux_select" ON documents_animaux FOR SELECT USING (true);
CREATE POLICY "documents_animaux_write" ON documents_animaux
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = documents_animaux.uid_eleveur AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
    OR EXISTS (SELECT 1 FROM users u WHERE u.uid = (auth.jwt() ->> 'sub') AND u.email IS NOT NULL AND u.email = (documents_animaux.metadata ->> 'acquereur_email'))
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = documents_animaux.uid_eleveur AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
    OR EXISTS (SELECT 1 FROM users u WHERE u.uid = (auth.jwt() ->> 'sub') AND u.email IS NOT NULL AND u.email = (documents_animaux.metadata ->> 'acquereur_email'))
  );
-- Note : signature/refus/annulation/sélection femelle/correction contact par
-- l'acquéreur (anonyme ou connecté hors éleveur) passent désormais par les
-- routes api/contracts/[id]/* (service_role) — aucune policy anon nécessaire.

-- ── contract_signers (corrige le bug auth.uid(), table sans usage live) ──
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE contract_signers ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'contract_signers'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.contract_signers', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "contract_signers_select" ON contract_signers FOR SELECT USING (true);
CREATE POLICY "contract_signers_write" ON contract_signers
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM documents_animaux d
      WHERE d.id = contract_signers.document_id
        AND (
          d.uid_eleveur = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = d.uid_eleveur AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM documents_animaux d
      WHERE d.id = contract_signers.document_id
        AND (
          d.uid_eleveur = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = d.uid_eleveur AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    )
  );

-- ── contract_audit (corrige le bug auth.uid() — lecture jamais possible avant) ─
DROP POLICY IF EXISTS "audit_select" ON contract_audit;
CREATE POLICY "audit_select" ON contract_audit
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM documents_animaux d
      WHERE d.id = contract_audit.document_id
        AND (
          d.uid_eleveur = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = d.uid_eleveur AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
          OR public.is_admin_uid((auth.jwt() ->> 'sub'))
        )
    )
  );
-- audit_insert (INSERT WITH CHECK (document_id existe)) reste inchangée —
-- log_contract_action est SECURITY DEFINER et contourne cette policy de
-- toute façon ; c'est la seule voie d'écriture, cohérent avec l'immuabilité
-- voulue de ce journal (pas d'UPDATE/DELETE, déjà le cas).

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('documents_animaux','contract_signers','contract_audit')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('documents_animaux','contract_signers')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- CREATE POLICY "docs_select" ON documents_animaux FOR SELECT USING (true);
-- CREATE POLICY "docs_insert" ON documents_animaux FOR INSERT WITH CHECK (true);
-- CREATE POLICY "docs_update" ON documents_animaux FOR UPDATE USING (true);
-- CREATE POLICY "docs_delete" ON documents_animaux FOR DELETE USING (true);
-- CREATE POLICY "signers_select" ON contract_signers FOR SELECT USING (
--   EXISTS (SELECT 1 FROM documents_animaux d WHERE d.id = document_id AND (d.token IS NOT NULL OR auth.uid()::text = d.uid_eleveur))
-- );
-- CREATE POLICY "signers_insert" ON contract_signers FOR INSERT WITH CHECK (
--   EXISTS (SELECT 1 FROM documents_animaux d WHERE d.id = document_id AND auth.uid()::text = d.uid_eleveur)
-- );
-- CREATE POLICY "signers_update" ON contract_signers FOR UPDATE USING (
--   EXISTS (SELECT 1 FROM documents_animaux d WHERE d.id = document_id AND (auth.uid()::text = d.uid_eleveur OR d.token IS NOT NULL))
-- );
-- CREATE POLICY "signers_delete" ON contract_signers FOR DELETE USING (
--   EXISTS (SELECT 1 FROM documents_animaux d WHERE d.id = document_id AND auth.uid()::text = d.uid_eleveur)
-- );
-- DROP POLICY IF EXISTS "audit_select" ON contract_audit;
-- CREATE POLICY "audit_select" ON contract_audit FOR SELECT USING (
--   EXISTS (SELECT 1 FROM documents_animaux d WHERE d.id = document_id AND auth.uid()::text = d.uid_eleveur)
-- );
