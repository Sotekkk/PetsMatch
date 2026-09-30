-- ════════════════════════════════════════════════════════════════════════
-- RLS lecture : factures, pension_factures, devis, cessions,
-- certificats_engagement, documents_animaux, contract_signers.
--
-- Avant : écritures déjà protégées, mais LECTURE « USING (true) » →
-- n'importe qui, sans compte, lisait toutes les factures (noms, adresses,
-- montants, SIRET clients), devis, cessions (acquéreurs, prix,
-- signatures), certificats d'engagement et contrats.
--
-- Après, lecture réservée à :
--   • le compte émetteur (pm_acces_compte, migration agenda/rdv) :
--       – factures / devis / factures de pension : titulaire + cogérant
--         (les employés n'ont pas de droit « facturation » aujourd'hui ;
--         créer ce droit suffira pour le leur ouvrir) ;
--       – documents / cessions / certificats : + employés actifs du profil
--         (fiche animal ouverte par un employé) ;
--   • le destinataire : client, acquéreur (par uid, ou par e-mail tant que
--     son compte n'est pas relié), propriétaire actuel de l'animal pour
--     ses documents ;
--   • quiconque présente LE token de la ligne dans l'en-tête HTTP
--     `x-pm-token` (pages publiques /facture/[token], /devis/[token],
--     /signer-contrat/[token], /signer-cession/[token],
--     /certificat/[token], /facture-pension/[token], écran de signature
--     de l'appli) : le lien secret ouvre SA ligne et seulement elle.
--     ⚠ Nécessite le code qui envoie cet en-tête (appli + site).
--   • admin (users.is_admin).
-- Écritures : policies existantes inchangées.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

-- Token présenté par la requête (en-tête x-pm-token), NULL sinon.
CREATE OR REPLACE FUNCTION public.pm_token_requete()
RETURNS text
LANGUAGE sql STABLE
AS $$
  SELECT nullif(current_setting('request.headers', true)::json ->> 'x-pm-token', '');
$$;
GRANT EXECUTE ON FUNCTION public.pm_token_requete() TO anon, authenticated;

-- E-mail du jeton Firebase (acquéreur pas encore relié par uid).
CREATE OR REPLACE FUNCTION public.pm_email_jeton()
RETURNS text
LANGUAGE sql STABLE
AS $$
  SELECT nullif(lower(auth.jwt() ->> 'email'), '');
$$;
GRANT EXECUTE ON FUNCTION public.pm_email_jeton() TO anon, authenticated;

-- ── factures ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS factures_select_all ON public.factures;
DROP POLICY IF EXISTS factures_select ON public.factures;
CREATE POLICY factures_select ON public.factures
  FOR SELECT TO anon, authenticated
  USING (
    public.pm_acces_compte(uid_eleveur, profile_id::text, ARRAY['facturation'])
    OR (auth.jwt() ->> 'sub') = client_uid
    OR token = public.pm_token_requete()
    OR public.is_admin_uid(auth.jwt() ->> 'sub')
  );

-- ── pension_factures ───────────────────────────────────────────────────
DROP POLICY IF EXISTS pension_factures_select_all ON public.pension_factures;
DROP POLICY IF EXISTS pension_factures_select ON public.pension_factures;
CREATE POLICY pension_factures_select ON public.pension_factures
  FOR SELECT TO anon, authenticated
  USING (
    public.pm_acces_compte(pro_uid, pro_profile_id::text, ARRAY['facturation'])
    OR (auth.jwt() ->> 'sub') = proprietaire_uid
    OR token::text = public.pm_token_requete()
    OR public.is_admin_uid(auth.jwt() ->> 'sub')
  );

-- ── devis ──────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS devis_select ON public.devis;
CREATE POLICY devis_select ON public.devis
  FOR SELECT TO anon, authenticated
  USING (
    public.pm_acces_compte(pro_uid, pro_profile_id::text, ARRAY['facturation'])
    OR (auth.jwt() ->> 'sub') = client_uid
    OR token_acceptation = public.pm_token_requete()
    OR public.is_admin_uid(auth.jwt() ->> 'sub')
  );

-- ── cessions ───────────────────────────────────────────────────────────
DROP POLICY IF EXISTS cessions_select ON public.cessions;
CREATE POLICY cessions_select ON public.cessions
  FOR SELECT TO anon, authenticated
  USING (
    public.pm_acces_compte(uid_eleveur, pro_profile_id::text)
    OR (auth.jwt() ->> 'sub') = uid_acquereur
    OR lower(email_acquereur) = public.pm_email_jeton()
    OR token = public.pm_token_requete()
    OR public.is_admin_uid(auth.jwt() ->> 'sub')
  );

-- ── certificats_engagement ─────────────────────────────────────────────
DROP POLICY IF EXISTS certificats_engagement_select_all ON public.certificats_engagement;
DROP POLICY IF EXISTS certificats_engagement_select ON public.certificats_engagement;
CREATE POLICY certificats_engagement_select ON public.certificats_engagement
  FOR SELECT TO anon, authenticated
  USING (
    public.pm_acces_compte(cedant_uid, NULL)
    OR (auth.jwt() ->> 'sub') = acquereur_uid
    OR lower(acquereur_email) = public.pm_email_jeton()
    OR token_signature = public.pm_token_requete()
    OR public.is_admin_uid(auth.jwt() ->> 'sub')
  );

-- ── documents_animaux ──────────────────────────────────────────────────
DROP POLICY IF EXISTS documents_animaux_select ON public.documents_animaux;
CREATE POLICY documents_animaux_select ON public.documents_animaux
  FOR SELECT TO anon, authenticated
  USING (
    public.pm_acces_compte(uid_eleveur, pro_profile_id::text)
    OR (auth.jwt() ->> 'sub') = uid_acquereur
    OR token = public.pm_token_requete()
    OR EXISTS (SELECT 1 FROM public.animaux_proprietes ap
               WHERE ap.animal_id = documents_animaux.animal_id
                 AND ap.uid_proprio = (auth.jwt() ->> 'sub'))
    OR public.is_admin_uid(auth.jwt() ->> 'sub')
  );

-- ── animaux : l'animal d'un contrat / cession / certificat ouvert par lien ─
-- Les pages de signature chargent l'animal lié (nom, race, identification…)
-- dans la même requête ; un acquéreur sans compte ne le voyait pas
-- (animaux: null → contrat affiché sans l'animal). Le lien secret ouvre
-- désormais l'animal concerné, et lui seul.
DROP POLICY IF EXISTS animaux_select_via_lien ON public.animaux;
CREATE POLICY animaux_select_via_lien ON public.animaux
  FOR SELECT TO anon, authenticated
  USING (
    public.pm_token_requete() IS NOT NULL AND (
      EXISTS (SELECT 1 FROM public.documents_animaux d
              WHERE d.animal_id = animaux.id AND d.token = public.pm_token_requete())
      OR EXISTS (SELECT 1 FROM public.cessions c
                 WHERE c.animal_id = animaux.id AND c.token = public.pm_token_requete())
      OR EXISTS (SELECT 1 FROM public.certificats_engagement ce
                 WHERE ce.animal_id = animaux.id AND ce.token_signature = public.pm_token_requete())
    )
  );

-- ── contract_signers : visibles avec le document ───────────────────────
DROP POLICY IF EXISTS contract_signers_select ON public.contract_signers;
CREATE POLICY contract_signers_select ON public.contract_signers
  FOR SELECT TO anon, authenticated
  USING (EXISTS (SELECT 1 FROM public.documents_animaux d
                 WHERE d.id = contract_signers.document_id));

COMMIT;
