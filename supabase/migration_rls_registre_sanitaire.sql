-- ══════════════════════════════════════════════════════════════════════════
-- registre_sanitaire — RLS jamais activée (alerte Supabase « RLS disabled »)
-- ══════════════════════════════════════════════════════════════════════════
-- Seule table exposée sans RLS (203/204) : ses lignes (actes sanitaires des
-- élevages) étaient lisibles, modifiables et supprimables par n'importe qui
-- avec la clé publique.
--
-- Qui écrit aujourd'hui (vérifié dans le code, 30/09/2026) :
--   - éleveur (appli RegistreHelper.writeActe + pages registre, site) :
--     uid_eleveur = lui-même ;
--   - employé / cogérant depuis l'appli : writeActe écrit sous LEUR propre uid
--     (limite existante, inchangée ici) ;
--   - employé / cogérant depuis la fiche animal du site : sous l'uid de
--     l'ÉLEVEUR (animal.uid_eleveur) → doivent avoir accès aux lignes de
--     leur employeur ;
--   - acquéreur d'un animal cédé (fiche du site) : écrivait dans le registre
--     de l'éleveur d'origine → désormais refusé (voulu).
--
-- Règle (modèle can_access_inventaire, SCOPÉE PAR PROFIL — pas de mélange
-- entre les profils d'un même compte) :
--   propriétaire (uid_eleveur) ........ lecture + écriture (tous ses profils :
--                                        même personne)
--   cogérant actif .................... lecture + écriture, uniquement sur le
--                                        profil d'élevage de SA cogérance
--                                        (elevage_cogerants.elevage_profile_id)
--   employé actif ..................... uniquement sur le profil où il est
--                                        employé (employes.eleveur_profile_id) ;
--                                        écriture si CET emploi a write_sante /
--                                        write_repro / write_animaux
--   tout autre compte ................. rien
-- Lignes sans eleveur_profile_id (anciennes) : pas de profil connu → règle
-- par uid seulement. Ligne dont le profil est celui de l'employé lui-même :
-- acceptée (la fiche animal du site écrit le profil ACTIF du visiteur — bug
-- à corriger côté code, toléré ici pour ne pas casser la saisie).
--
-- ⚠️ Testé sur le staging avant la prod (propriétaire, cogérant, employés
-- avec/sans droits, autre profil de l'employeur, tiers, non connecté).
-- ══════════════════════════════════════════════════════════════════════════

-- Ordre : policies d'abord (elles dépendent de la fonction), puis l'éventuelle
-- première version sans profil (appliquée uniquement sur le staging).
DROP POLICY IF EXISTS "registre_sanitaire_select" ON public.registre_sanitaire;
DROP POLICY IF EXISTS "registre_sanitaire_insert" ON public.registre_sanitaire;
DROP POLICY IF EXISTS "registre_sanitaire_update" ON public.registre_sanitaire;
DROP POLICY IF EXISTS "registre_sanitaire_delete" ON public.registre_sanitaire;
DROP FUNCTION IF EXISTS public.can_access_registre_sanitaire(TEXT, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION public.can_access_registre_sanitaire(
  p_uid_eleveur TEXT, p_profile_id UUID, p_uid TEXT, p_require_write BOOLEAN DEFAULT false)
RETURNS BOOLEAN
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_uid IS NOT NULL AND p_uid_eleveur IS NOT NULL AND (
    p_uid_eleveur = p_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = p_uid_eleveur AND c.uid_cogerant = p_uid
        AND c.statut = 'actif' AND c.date_fin IS NULL
        AND (p_profile_id IS NULL OR c.elevage_profile_id IS NULL
             OR c.elevage_profile_id = p_profile_id OR c.profile_id_cogerant = p_profile_id)
    )
    OR EXISTS (
      SELECT 1 FROM employes e
      WHERE e.uid_eleveur = p_uid_eleveur AND e.uid_employe = p_uid AND e.actif = true
        AND (p_profile_id IS NULL OR e.eleveur_profile_id = p_profile_id OR e.employe_profile_id = p_profile_id)
        AND (
          NOT p_require_write
          OR EXISTS (
            SELECT 1 FROM employe_permissions ep
            WHERE ep.eleveur_profile_id = e.eleveur_profile_id
              AND ep.employe_profile_id = e.employe_profile_id
              AND ep.permission IN ('write_sante', 'write_repro', 'write_animaux')
          )
        )
    )
  );
$$;
GRANT EXECUTE ON FUNCTION public.can_access_registre_sanitaire(TEXT, UUID, TEXT, BOOLEAN) TO anon, authenticated;

ALTER TABLE public.registre_sanitaire ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "registre_sanitaire_select" ON public.registre_sanitaire;
CREATE POLICY "registre_sanitaire_select" ON public.registre_sanitaire
  FOR SELECT USING (public.can_access_registre_sanitaire(uid_eleveur, eleveur_profile_id, (auth.jwt() ->> 'sub'), false));

DROP POLICY IF EXISTS "registre_sanitaire_insert" ON public.registre_sanitaire;
CREATE POLICY "registre_sanitaire_insert" ON public.registre_sanitaire
  FOR INSERT WITH CHECK (public.can_access_registre_sanitaire(uid_eleveur, eleveur_profile_id, (auth.jwt() ->> 'sub'), true));

DROP POLICY IF EXISTS "registre_sanitaire_update" ON public.registre_sanitaire;
CREATE POLICY "registre_sanitaire_update" ON public.registre_sanitaire
  FOR UPDATE USING (public.can_access_registre_sanitaire(uid_eleveur, eleveur_profile_id, (auth.jwt() ->> 'sub'), true))
  WITH CHECK (public.can_access_registre_sanitaire(uid_eleveur, eleveur_profile_id, (auth.jwt() ->> 'sub'), true));

DROP POLICY IF EXISTS "registre_sanitaire_delete" ON public.registre_sanitaire;
CREATE POLICY "registre_sanitaire_delete" ON public.registre_sanitaire
  FOR DELETE USING (public.can_access_registre_sanitaire(uid_eleveur, eleveur_profile_id, (auth.jwt() ->> 'sub'), true));

-- TRUNCATE contourne la RLS : on le retire aux rôles publics.
REVOKE TRUNCATE ON public.registre_sanitaire FROM anon, authenticated;

-- Vérification
SELECT relrowsecurity AS rls_active FROM pg_class WHERE oid = 'public.registre_sanitaire'::regclass;
SELECT policyname, cmd FROM pg_policies WHERE tablename = 'registre_sanitaire' ORDER BY cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "registre_sanitaire_select" ON public.registre_sanitaire;
-- DROP POLICY IF EXISTS "registre_sanitaire_insert" ON public.registre_sanitaire;
-- DROP POLICY IF EXISTS "registre_sanitaire_update" ON public.registre_sanitaire;
-- DROP POLICY IF EXISTS "registre_sanitaire_delete" ON public.registre_sanitaire;
-- ALTER TABLE public.registre_sanitaire DISABLE ROW LEVEL SECURITY;
-- DROP FUNCTION IF EXISTS public.can_access_registre_sanitaire(TEXT, UUID, TEXT, BOOLEAN);
-- GRANT TRUNCATE ON public.registre_sanitaire TO anon, authenticated;
