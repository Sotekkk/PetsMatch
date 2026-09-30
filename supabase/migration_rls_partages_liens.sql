-- ════════════════════════════════════════════════════════════════════════
-- RLS : partages par lien + écritures encore ouvertes (groupe 5a/5b).
-- ⚠ À appliquer APRÈS migration_rls_documents_factures.sql
--   (pm_token_requete) et migration_rls_agenda_rdv_notifs_registre.sql
--   (pm_acces_compte).
--
-- Avant :
--   • partage_tokens (accès vétérinaire au carnet de santé), album_partage,
--     animal_claims, partage_animal, partage_suivi_education :
--     SELECT USING (true) → n'importe qui listait TOUS les tokens et
--     ouvrait carnets de santé, albums privés, suivis d'éducation… ;
--     partage_tokens : UPDATE USING (true) ; animal_claims : UPDATE ouvert
--     à tous tant que la réclamation est « en_attente » ;
--   • à l'inverse, les pages ouvertes par lien SANS compte ne voyaient pas
--     les données liées (photos de l'album, animal, suivi d'éducation) :
--     tables fermées aux visiteurs → pages vides (bug existant) ;
--   • bloquages (ALL true), favoris et likes (« Allow all » ALL true) :
--     écriture ouverte à tous.
--
-- Après :
--   • le lien secret = en-tête HTTP x-pm-token (pm_token_requete) ;
--     un lien n'est valable que s'il est actif et non expiré ;
--   • tables de partage : créateur / destinataire / porteur du lien ;
--   • données liées, pour CET album ou CET animal uniquement :
--       – album_partage → albums_photo, album_photos ;
--       – animal ouvert par lien (pm_animal_via_lien) → animaux ;
--       – accès vétérinaire (partage_tokens) → 6 tables de santé ;
--       – suivi d'éducation (partage_suivi_education) → objectifs,
--         exercices attribués, séances ;
--   • bloquages : les siens (le bloqué voit qu'il l'est) ; favoris / likes :
--     lecture publique inchangée, écriture = les siens.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── Animal ouvert par un lien valide ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.pm_animal_via_lien(p_animal_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.pm_token_requete() IS NOT NULL AND p_animal_id IS NOT NULL AND (
    EXISTS (SELECT 1 FROM documents_animaux d
            WHERE d.animal_id = p_animal_id AND d.token = public.pm_token_requete())
    OR EXISTS (SELECT 1 FROM cessions c
               WHERE c.animal_id = p_animal_id AND c.token = public.pm_token_requete())
    OR EXISTS (SELECT 1 FROM certificats_engagement ce
               WHERE ce.animal_id = p_animal_id AND ce.token_signature = public.pm_token_requete())
    OR EXISTS (SELECT 1 FROM partage_animal pa
               WHERE pa.animal_id = p_animal_id AND pa.token::text = public.pm_token_requete()
                 AND coalesce(pa.actif, true) AND (pa.expire_at IS NULL OR pa.expire_at > now()))
    OR EXISTS (SELECT 1 FROM partage_suivi_education ps
               WHERE ps.animal_id = p_animal_id AND ps.token = public.pm_token_requete()
                 AND coalesce(ps.actif, true) AND (ps.expire_at IS NULL OR ps.expire_at > now()))
    OR EXISTS (SELECT 1 FROM animal_claims ac
               WHERE ac.animal_id = p_animal_id AND ac.token = public.pm_token_requete())
    OR EXISTS (SELECT 1 FROM partage_tokens pt
               WHERE pt.animal_id = p_animal_id AND pt.token = public.pm_token_requete()
                 AND (pt.expires_at IS NULL OR pt.expires_at > now()))
  );
$$;
GRANT EXECUTE ON FUNCTION public.pm_animal_via_lien(text) TO anon, authenticated;

-- Accès vétérinaire valide (carnet de santé).
CREATE OR REPLACE FUNCTION public.pm_sante_via_lien(p_animal_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.pm_token_requete() IS NOT NULL AND EXISTS (
    SELECT 1 FROM partage_tokens pt
    WHERE pt.animal_id = p_animal_id AND pt.token = public.pm_token_requete()
      AND (pt.expires_at IS NULL OR pt.expires_at > now())
  );
$$;
GRANT EXECUTE ON FUNCTION public.pm_sante_via_lien(text) TO anon, authenticated;

-- Suivi d'éducation partagé valide.
CREATE OR REPLACE FUNCTION public.pm_suivi_via_lien(p_animal_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.pm_token_requete() IS NOT NULL AND EXISTS (
    SELECT 1 FROM partage_suivi_education ps
    WHERE ps.animal_id = p_animal_id AND ps.token = public.pm_token_requete()
      AND coalesce(ps.actif, true) AND (ps.expire_at IS NULL OR ps.expire_at > now())
  );
$$;
GRANT EXECUTE ON FUNCTION public.pm_suivi_via_lien(text) TO anon, authenticated;

-- Album partagé valide.
CREATE OR REPLACE FUNCTION public.pm_album_via_lien(p_album_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.pm_token_requete() IS NOT NULL AND EXISTS (
    SELECT 1 FROM album_partage ap
    WHERE ap.album_id = p_album_id AND ap.token = public.pm_token_requete()
      AND coalesce(ap.actif, true) AND (ap.expire_at IS NULL OR ap.expire_at > now())
  );
$$;
GRANT EXECUTE ON FUNCTION public.pm_album_via_lien(uuid) TO anon, authenticated;

-- ── animaux : remplace la policy du groupe 4 par la fonction commune ───
DROP POLICY IF EXISTS animaux_select_via_lien ON public.animaux;
CREATE POLICY animaux_select_via_lien ON public.animaux
  FOR SELECT TO anon, authenticated
  USING (public.pm_animal_via_lien(id));

-- ── partage_tokens (accès vétérinaire) ─────────────────────────────────
DROP POLICY IF EXISTS partage_tokens_select ON public.partage_tokens;
CREATE POLICY partage_tokens_select ON public.partage_tokens
  FOR SELECT TO anon, authenticated
  USING ((auth.jwt() ->> 'sub') = owner_id OR token = public.pm_token_requete());
DROP POLICY IF EXISTS partage_tokens_update ON public.partage_tokens;
CREATE POLICY partage_tokens_update ON public.partage_tokens
  FOR UPDATE TO anon, authenticated
  USING ((auth.jwt() ->> 'sub') = owner_id OR token = public.pm_token_requete())
  WITH CHECK ((auth.jwt() ->> 'sub') = owner_id OR token = public.pm_token_requete());

-- ── Albums ─────────────────────────────────────────────────────────────
-- albums_photo_select / album_photos_select rendaient lisible par TOUS
-- (sans token) tout album ayant un lien de partage actif, photos
-- comprises. Réécrites sans cette clause : l'accès par lien passe par
-- pm_album_via_lien (token vérifié). Le propriétaire / client passe par
-- une fonction SECURITY DEFINER (évite la boucle de policies
-- album_partage ↔ albums_photo).
CREATE OR REPLACE FUNCTION public.pm_album_acteur(p_album_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (auth.jwt() ->> 'sub') IS NOT NULL AND EXISTS (
    SELECT 1 FROM albums_photo a
    WHERE a.id = p_album_id
      AND ((auth.jwt() ->> 'sub') = a.client_uid OR public.pm_acces_compte(a.pro_uid, NULL))
  );
$$;
GRANT EXECUTE ON FUNCTION public.pm_album_acteur(uuid) TO anon, authenticated;

DROP POLICY IF EXISTS albums_photo_select ON public.albums_photo;
CREATE POLICY albums_photo_select ON public.albums_photo
  FOR SELECT TO anon, authenticated
  USING (public.pm_album_acteur(id));
DROP POLICY IF EXISTS album_photos_select ON public.album_photos;
CREATE POLICY album_photos_select ON public.album_photos
  FOR SELECT TO anon, authenticated
  USING (public.pm_album_acteur(album_id));

DROP POLICY IF EXISTS album_partage_select ON public.album_partage;
CREATE POLICY album_partage_select ON public.album_partage
  FOR SELECT TO anon, authenticated
  USING (token = public.pm_token_requete() OR public.pm_album_acteur(album_id));

-- ── animal_claims ──────────────────────────────────────────────────────
DROP POLICY IF EXISTS animal_claims_select ON public.animal_claims;
CREATE POLICY animal_claims_select ON public.animal_claims
  FOR SELECT TO anon, authenticated
  USING (
    (auth.jwt() ->> 'sub') IN (created_by_uid, claimed_by_uid)
    OR token = public.pm_token_requete()
  );
DROP POLICY IF EXISTS animal_claims_update ON public.animal_claims;
CREATE POLICY animal_claims_update ON public.animal_claims
  FOR UPDATE TO anon, authenticated
  USING (
    (auth.jwt() ->> 'sub') = created_by_uid
    OR (statut = 'en_attente' AND token = public.pm_token_requete()
        AND (auth.jwt() ->> 'sub') IS NOT NULL)
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = created_by_uid
    OR ((auth.jwt() ->> 'sub') = claimed_by_uid AND token = public.pm_token_requete())
  );

-- ── partage_animal ─────────────────────────────────────────────────────
DROP POLICY IF EXISTS partage_animal_select ON public.partage_animal;
CREATE POLICY partage_animal_select ON public.partage_animal
  FOR SELECT TO anon, authenticated
  USING (
    (auth.jwt() ->> 'sub') IN (uid_partageur, uid_destinataire)
    OR token::text = public.pm_token_requete()
  );

-- ── partage_suivi_education ────────────────────────────────────────────
DROP POLICY IF EXISTS partage_suivi_education_select_all ON public.partage_suivi_education;
DROP POLICY IF EXISTS partage_suivi_education_select ON public.partage_suivi_education;
CREATE POLICY partage_suivi_education_select ON public.partage_suivi_education
  FOR SELECT TO anon, authenticated
  USING (
    public.pm_acces_compte(pro_uid, pro_profile_id::text)
    OR token = public.pm_token_requete()
    OR EXISTS (SELECT 1 FROM public.animaux_proprietes ap
               WHERE ap.animal_id = partage_suivi_education.animal_id
                 AND ap.uid_proprio = (auth.jwt() ->> 'sub'))
  );

-- ── Données liées ouvertes par lien ────────────────────────────────────
DROP POLICY IF EXISTS albums_photo_select_via_lien ON public.albums_photo;
CREATE POLICY albums_photo_select_via_lien ON public.albums_photo
  FOR SELECT TO anon, authenticated USING (public.pm_album_via_lien(id));
DROP POLICY IF EXISTS album_photos_select_via_lien ON public.album_photos;
CREATE POLICY album_photos_select_via_lien ON public.album_photos
  FOR SELECT TO anon, authenticated USING (public.pm_album_via_lien(album_id));

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['vaccinations','traitements','visites','vermifuges','antiparasitaires','allergies'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_select_via_lien', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO anon, authenticated USING (public.pm_sante_via_lien(animal_id))',
                   t || '_select_via_lien', t);
  END LOOP;
  FOREACH t IN ARRAY ARRAY['education_objectifs','exercices_attribues','education_progression'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_select_via_lien', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO anon, authenticated USING (public.pm_suivi_via_lien(animal_id))',
                   t || '_select_via_lien', t);
  END LOOP;
END $$;

-- ── bloquages / favoris / likes ────────────────────────────────────────
DROP POLICY IF EXISTS bloquages_all ON public.bloquages;
DROP POLICY IF EXISTS bloquages_select ON public.bloquages;
DROP POLICY IF EXISTS bloquages_insert ON public.bloquages;
DROP POLICY IF EXISTS bloquages_delete ON public.bloquages;
CREATE POLICY bloquages_select ON public.bloquages
  FOR SELECT TO anon, authenticated
  USING ((auth.jwt() ->> 'sub') IN (uid, blocked_uid));
CREATE POLICY bloquages_insert ON public.bloquages
  FOR INSERT TO anon, authenticated
  WITH CHECK ((auth.jwt() ->> 'sub') = uid);
CREATE POLICY bloquages_delete ON public.bloquages
  FOR DELETE TO anon, authenticated
  USING ((auth.jwt() ->> 'sub') = uid);
-- upsert du site (messages/page.tsx) → UPDATE possible sur conflit.
DROP POLICY IF EXISTS bloquages_update ON public.bloquages;
CREATE POLICY bloquages_update ON public.bloquages
  FOR UPDATE TO anon, authenticated
  USING ((auth.jwt() ->> 'sub') = uid)
  WITH CHECK ((auth.jwt() ->> 'sub') = uid);

DROP POLICY IF EXISTS "Allow all" ON public.favoris;
DROP POLICY IF EXISTS "Allow all" ON public.likes;
-- favoris_own_write / likes_own_write (les siens) et *_public_read conservées.

COMMIT;
