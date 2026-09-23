-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 25/N : forum + signalements
--   forum_sujets, forum_reponses, signalements
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- forum_sujets/forum_reponses : USING(true) — SELECT reste public (forum
-- ouvert par conception), écriture verrouillée à l'auteur + un admin
-- (public.is_admin_uid, vague 13/N — épingler/modérer, jamais câblé côté
-- appli mais prévu par la colonne `epingle`).
--
-- signalements : AUCUNE RLS jusqu'ici (ni ENABLE ROW LEVEL SECURITY, ni
-- policy) — n'importe qui pouvait lire QUI a signalé QUOI (reporter_uid,
-- risque de représailles) et les notes de modération admin_note, et
-- modifier/supprimer n'importe quel signalement. Verrouillé : un
-- utilisateur voit/crée ses propres signalements ; un admin voit/traite
-- tout ; un admin/modérateur d'un groupe voit/traite les signalements
-- rattachés à SON groupe (colonne groupe_id, ajoutée pour ça — cf.
-- migration_groupes_roles_signalements.sql).
--
-- ⚠️ À TESTER après exécution :
--   1. Le forum (sujets + réponses) s'affiche normalement pour tout le
--      monde ; créer un sujet/une réponse fonctionne pour son auteur.
--   2. Signaler un contenu (annonce, profil, post de groupe...)
--      fonctionne toujours.
--   3. Un signalement n'est visible que par celui qui l'a créé (pas par
--      un autre utilisateur lambda).
--   4. Le panel de modération admin voit tous les signalements ; un
--      admin/modérateur de groupe voit ceux de son groupe.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── forum_sujets, forum_reponses ──────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'forum_sujets'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.forum_sujets', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "forum_sujets_select" ON forum_sujets FOR SELECT USING (true);

CREATE POLICY "forum_sujets_insert" ON forum_sujets
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = auteur_uid);

CREATE POLICY "forum_sujets_update" ON forum_sujets
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = auteur_uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = auteur_uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );

CREATE POLICY "forum_sujets_delete" ON forum_sujets
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = auteur_uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );

DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'forum_reponses'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.forum_reponses', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "forum_reponses_select" ON forum_reponses FOR SELECT USING (true);

CREATE POLICY "forum_reponses_insert" ON forum_reponses
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = auteur_uid);

CREATE POLICY "forum_reponses_update" ON forum_reponses
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = auteur_uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = auteur_uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );

CREATE POLICY "forum_reponses_delete" ON forum_reponses
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = auteur_uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );

-- ── signalements (aucune RLS jusqu'ici) ───────────────────────────────────
ALTER TABLE signalements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "signalements_select" ON signalements
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = reporter_uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
    OR (groupe_id IS NOT NULL AND public.is_admin_or_moderateur_of_groupe(groupe_id, (auth.jwt() ->> 'sub')))
  );

CREATE POLICY "signalements_insert" ON signalements
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = reporter_uid);

-- Traitement (statut/admin_note/handled_*) réservé aux admins et, pour un
-- signalement de contenu de groupe, aux admins/modérateurs de CE groupe —
-- jamais à l'auteur du signalement lui-même (pas de auto-validation).
CREATE POLICY "signalements_update" ON signalements
  FOR UPDATE USING (
    public.is_admin_uid((auth.jwt() ->> 'sub'))
    OR (groupe_id IS NOT NULL AND public.is_admin_or_moderateur_of_groupe(groupe_id, (auth.jwt() ->> 'sub')))
  )
  WITH CHECK (
    public.is_admin_uid((auth.jwt() ->> 'sub'))
    OR (groupe_id IS NOT NULL AND public.is_admin_or_moderateur_of_groupe(groupe_id, (auth.jwt() ->> 'sub')))
  );

CREATE POLICY "signalements_delete" ON signalements
  FOR DELETE USING (public.is_admin_uid((auth.jwt() ->> 'sub')));

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('forum_sujets','forum_reponses','signalements')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('forum_sujets','forum_reponses','signalements')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- CREATE POLICY "fs_select" ON forum_sujets FOR SELECT USING (true);
-- CREATE POLICY "fs_insert" ON forum_sujets FOR INSERT WITH CHECK (true);
-- CREATE POLICY "fs_update" ON forum_sujets FOR UPDATE USING (true);
-- CREATE POLICY "fs_delete" ON forum_sujets FOR DELETE USING (true);
-- CREATE POLICY "fr_all" ON forum_reponses FOR ALL USING (true);
-- ALTER TABLE signalements DISABLE ROW LEVEL SECURITY;
