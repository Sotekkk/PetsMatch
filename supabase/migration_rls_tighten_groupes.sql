-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 24/N : groupes communautaires
--   groupes, groupes_membres, groupe_posts, groupe_post_commentaires,
--   groupe_post_likes, groupe_commentaire_likes
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- Toutes ces tables étaient en USING(true) (souvent FOR ALL). Vérifié dans
-- le code (communaute/groupes/[id]/page.tsx) : le flag `prive` d'un groupe
-- ne restreint QUE la liste des membres (visible en entier aux membres,
-- limitée aux admins/modérateurs pour un non-membre) — jamais le contenu
-- des posts, qui reste public par conception. SELECT reste donc public
-- partout ; le verrouillage porte sur l'écriture et sur la liste des
-- membres d'un groupe privé.
--
-- Rôles (groupes_membres.role, vague « groupes_roles_signalements ») :
-- admin > modérateur > membre — un admin/modérateur peut modérer le
-- contenu du groupe (épingler/masquer/supprimer un post ou commentaire
-- d'un autre membre) ; seul un admin modifie les réglages du groupe.
-- 3 fonctions SECURITY DEFINER dédiées, pour éviter l'auto-référence
-- (une policy sur groupes_membres qui interrogerait groupes_membres
-- directement provoquerait la même récursion que les incidents
-- animaux_proprietes/animal_access de ce chantier) :
--   - is_active_member_of_groupe   : membre actif (accepté), tout rôle
--   - is_admin_or_moderateur_of_groupe : modération de contenu
--   - is_admin_of_groupe           : réglages du groupe (créateur/admin)
--
-- ⚠️ À TESTER après exécution :
--   1. La liste des groupes, leurs posts, commentaires et likes restent
--      visibles publiquement (y compris les groupes privés — seule la
--      liste des membres change).
--   2. Créer un groupe, poster, commenter, liker fonctionnent toujours
--      pour un membre actif.
--   3. Un non-membre d'un groupe PRIVÉ ne voit que les admins/modérateurs
--      dans la liste des membres (comportement déjà en place côté appli,
--      maintenant aussi garanti côté base).
--   4. Un admin/modérateur peut modérer (masquer/supprimer) le post ou
--      commentaire d'un AUTRE membre ; un membre simple ne peut modifier
--      que les siens.
--   5. Rejoindre un groupe, accepter/refuser une demande, promouvoir un
--      membre modérateur, quitter un groupe fonctionnent toujours.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_active_member_of_groupe(p_groupe_id UUID, p_uid TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM groupes_membres gm
    WHERE gm.groupe_id = p_groupe_id AND gm.user_uid = p_uid AND gm.statut = 'active'
  );
$$;
GRANT EXECUTE ON FUNCTION public.is_active_member_of_groupe(UUID, TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.is_admin_or_moderateur_of_groupe(p_groupe_id UUID, p_uid TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM groupes_membres gm
    WHERE gm.groupe_id = p_groupe_id AND gm.user_uid = p_uid AND gm.statut = 'active'
      AND gm.role IN ('admin', 'moderateur')
  );
$$;
GRANT EXECUTE ON FUNCTION public.is_admin_or_moderateur_of_groupe(UUID, TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.is_admin_of_groupe(p_groupe_id UUID, p_uid TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM groupes g WHERE g.id = p_groupe_id AND g.createur_uid = p_uid
  )
  OR EXISTS (
    SELECT 1 FROM groupes_membres gm
    WHERE gm.groupe_id = p_groupe_id AND gm.user_uid = p_uid AND gm.statut = 'active' AND gm.role = 'admin'
  );
$$;
GRANT EXECUTE ON FUNCTION public.is_admin_of_groupe(UUID, TEXT) TO anon, authenticated;

-- ── groupes ────────────────────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'groupes'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.groupes', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "groupes_select" ON groupes FOR SELECT USING (true);

CREATE POLICY "groupes_insert" ON groupes
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = createur_uid);

CREATE POLICY "groupes_update" ON groupes
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = createur_uid
    OR public.is_admin_of_groupe(id, (auth.jwt() ->> 'sub'))
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = createur_uid
    OR public.is_admin_of_groupe(id, (auth.jwt() ->> 'sub'))
  );

CREATE POLICY "groupes_delete" ON groupes
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = createur_uid
    OR public.is_admin_of_groupe(id, (auth.jwt() ->> 'sub'))
  );

-- ── groupes_membres ────────────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'groupes_membres'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.groupes_membres', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "groupes_membres_select" ON groupes_membres
  FOR SELECT USING (
    role IN ('admin', 'moderateur')
    OR public.is_active_member_of_groupe(groupe_id, (auth.jwt() ->> 'sub'))
  );

-- Auto-attribution limitée : on ne peut jamais s'inscrire directement
-- admin/modérateur (uniquement promu ensuite par un admin existant via
-- UPDATE), et le statut 'active' immédiat n'est permis que si le groupe
-- n'est pas privé — sinon 'pending', comme déjà voulu côté appli
-- (communaute/groupes/[id]/page.tsx : statut = groupe.prive ? 'pending' : 'active').
CREATE POLICY "groupes_membres_insert" ON groupes_membres
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = user_uid
    AND role = 'membre'
    AND (
      statut = 'pending'
      OR (
        statut = 'active'
        AND NOT EXISTS (SELECT 1 FROM groupes g WHERE g.id = groupes_membres.groupe_id AND g.prive = true)
      )
    )
  );

-- WITH CHECK plus strict que USING : un self-update (pas admin/modérateur)
-- ne peut jamais aboutir à role != 'membre' — sinon un membre pourrait
-- s'auto-promouvoir admin via UPDATE au lieu de passer par l'INSERT
-- (déjà bloqué ci-dessus pour la même raison).
CREATE POLICY "groupes_membres_update" ON groupes_membres
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = user_uid
    OR public.is_admin_or_moderateur_of_groupe(groupe_id, (auth.jwt() ->> 'sub'))
  )
  WITH CHECK (
    public.is_admin_or_moderateur_of_groupe(groupe_id, (auth.jwt() ->> 'sub'))
    OR (
      (auth.jwt() ->> 'sub') = user_uid
      AND role = 'membre'
    )
  );

CREATE POLICY "groupes_membres_delete" ON groupes_membres
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = user_uid
    OR public.is_admin_or_moderateur_of_groupe(groupe_id, (auth.jwt() ->> 'sub'))
  );

-- ── groupe_posts ───────────────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'groupe_posts'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.groupe_posts', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "groupe_posts_select" ON groupe_posts FOR SELECT USING (true);

CREATE POLICY "groupe_posts_insert" ON groupe_posts
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = auteur_uid
    AND public.is_active_member_of_groupe(groupe_id, (auth.jwt() ->> 'sub'))
  );

CREATE POLICY "groupe_posts_update" ON groupe_posts
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = auteur_uid
    OR public.is_admin_or_moderateur_of_groupe(groupe_id, (auth.jwt() ->> 'sub'))
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = auteur_uid
    OR public.is_admin_or_moderateur_of_groupe(groupe_id, (auth.jwt() ->> 'sub'))
  );

CREATE POLICY "groupe_posts_delete" ON groupe_posts
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = auteur_uid
    OR public.is_admin_or_moderateur_of_groupe(groupe_id, (auth.jwt() ->> 'sub'))
  );

-- ── groupe_post_commentaires (rattaché via post_id → groupe_posts.groupe_id) ─
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'groupe_post_commentaires'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.groupe_post_commentaires', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "groupe_post_commentaires_select" ON groupe_post_commentaires FOR SELECT USING (true);

CREATE POLICY "groupe_post_commentaires_insert" ON groupe_post_commentaires
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = auteur_uid
    AND EXISTS (
      SELECT 1 FROM groupe_posts p
      WHERE p.id = groupe_post_commentaires.post_id
        AND public.is_active_member_of_groupe(p.groupe_id, (auth.jwt() ->> 'sub'))
    )
  );

CREATE POLICY "groupe_post_commentaires_update" ON groupe_post_commentaires
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = auteur_uid
    OR EXISTS (
      SELECT 1 FROM groupe_posts p
      WHERE p.id = groupe_post_commentaires.post_id
        AND public.is_admin_or_moderateur_of_groupe(p.groupe_id, (auth.jwt() ->> 'sub'))
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = auteur_uid
    OR EXISTS (
      SELECT 1 FROM groupe_posts p
      WHERE p.id = groupe_post_commentaires.post_id
        AND public.is_admin_or_moderateur_of_groupe(p.groupe_id, (auth.jwt() ->> 'sub'))
    )
  );

CREATE POLICY "groupe_post_commentaires_delete" ON groupe_post_commentaires
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = auteur_uid
    OR EXISTS (
      SELECT 1 FROM groupe_posts p
      WHERE p.id = groupe_post_commentaires.post_id
        AND public.is_admin_or_moderateur_of_groupe(p.groupe_id, (auth.jwt() ->> 'sub'))
    )
  );

-- ── groupe_post_likes, groupe_commentaire_likes (simple self) ─────────────
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['groupe_post_likes','groupe_commentaire_likes']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;

    EXECUTE format($f$ CREATE POLICY "%1$s_select" ON public.%1$I FOR SELECT USING (true) $f$, t);
    EXECUTE format($f$
      CREATE POLICY "%1$s_write" ON public.%1$I
        FOR ALL USING ((auth.jwt() ->> 'sub') = user_uid)
        WITH CHECK ((auth.jwt() ->> 'sub') = user_uid)
    $f$, t);
  END LOOP;
END $$;

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('groupes','groupes_membres','groupe_posts','groupe_post_commentaires','groupe_post_likes','groupe_commentaire_likes')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('groupes','groupes_membres','groupe_posts','groupe_post_commentaires','groupe_post_likes','groupe_commentaire_likes')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- CREATE POLICY "groupes_select" ON groupes FOR SELECT USING (true);
-- CREATE POLICY "groupes_insert" ON groupes FOR INSERT WITH CHECK (true);
-- CREATE POLICY "groupes_update" ON groupes FOR UPDATE USING (true);
-- CREATE POLICY "groupes_delete" ON groupes FOR DELETE USING (true);
-- CREATE POLICY "gm_select" ON groupes_membres FOR SELECT USING (true);
-- CREATE POLICY "gm_insert" ON groupes_membres FOR INSERT WITH CHECK (true);
-- CREATE POLICY "gm_update" ON groupes_membres FOR UPDATE USING (true);
-- CREATE POLICY "gm_delete" ON groupes_membres FOR DELETE USING (true);
-- CREATE POLICY "gp_select" ON groupe_posts FOR SELECT USING (true);
-- CREATE POLICY "gp_insert" ON groupe_posts FOR INSERT WITH CHECK (true);
-- CREATE POLICY "gp_update" ON groupe_posts FOR UPDATE USING (true);
-- CREATE POLICY "gp_delete" ON groupe_posts FOR DELETE USING (true);
-- CREATE POLICY "gpc_all" ON groupe_post_commentaires FOR ALL USING (true);
-- CREATE POLICY "gpl_all" ON groupe_post_likes FOR ALL USING (true);
-- CREATE POLICY "gcl_all" ON groupe_commentaire_likes FOR ALL USING (true);
-- DROP FUNCTION IF EXISTS public.is_active_member_of_groupe(UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.is_admin_or_moderateur_of_groupe(UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.is_admin_of_groupe(UUID, TEXT);
