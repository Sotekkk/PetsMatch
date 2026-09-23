-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 23/N : gamification / balades ludiques + admin
--   admin_alerts, activity_log, balades_ludiques, balades_ludiques_points,
--   balades_ludiques_progressions, balades_ludiques_validations,
--   balades_ludiques_avis, balades_ludiques_favoris, badges_obtenus,
--   joueurs_xp
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- admin_alerts avait `USING(true) WITH CHECK(true)` — n'importe qui
-- pouvait lire ET modifier les alertes de modération/validation des
-- comptes pro. Réservé aux admins (public.is_admin_uid, vague 13/N).
--
-- activity_log (journal XP des balades) n'avait aucune RLS du tout
-- (même hypothèse fausse que l'inventaire, vague 21/N) — réservé au
-- propriétaire de la ligne.
--
-- Le module balades ludiques (geocaching communautaire) avait du SELECT
-- public volontaire (parcours, avis, favoris, XP, badges obtenus — un
-- classement/une vitrine, cohérent, laissé tel quel) mais un
-- INSERT/UPDATE/DELETE quasi tout ouvert (`USING(true)`, seule
-- vérification : une colonne non NULLE) — n'importe qui pouvait modifier
-- ou supprimer le parcours ou l'avis de quelqu'un d'autre. Verrouillé au
-- créateur/joueur concerné. `badges` (catalogue) n'a jamais eu de policy
-- d'écriture — déjà correctement verrouillé (rien à faire).
--
-- ⚠️ À TESTER après exécution :
--   1. Les alertes admin (back-office) restent visibles uniquement par un
--      compte admin.
--   2. Le journal d'activité (balades enregistrées, XP, flamme) continue
--      de fonctionner pour l'utilisateur qui enregistre sa balade.
--   3. Créer/publier un parcours de balade ludique, y ajouter des points
--      d'intérêt, jouer un parcours (progression + validations par
--      étape), laisser un avis, mettre en favori : fonctionnent toujours
--      pour leur propriétaire respectif.
--   4. Le classement (XP, badges obtenus, parcours) reste visible
--      publiquement.
--   5. Impossible de modifier ou supprimer le parcours/avis d'un AUTRE
--      utilisateur (à tester si possible).
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── admin_alerts (réservé admin) ──────────────────────────────────────────
DROP POLICY IF EXISTS "admin_alerts_all" ON admin_alerts;
CREATE POLICY "admin_alerts_admin_only" ON admin_alerts
  FOR ALL USING (public.is_admin_uid((auth.jwt() ->> 'sub')))
  WITH CHECK (public.is_admin_uid((auth.jwt() ->> 'sub')));

-- ── activity_log (aucune RLS jusqu'ici — réservé au propriétaire) ─────────
ALTER TABLE activity_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "activity_log_owner" ON activity_log
  FOR ALL USING ((auth.jwt() ->> 'sub') = uid)
  WITH CHECK ((auth.jwt() ->> 'sub') = uid);

-- ── Tables balades ludiques scopées par une colonne uid directe ───────────
DO $$
DECLARE
  t TEXT;
  col TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['balades_ludiques:createur_uid', 'balades_ludiques_avis:user_uid', 'balades_ludiques_favoris:user_uid', 'badges_obtenus:user_uid', 'joueurs_xp:user_uid']
  LOOP
    col := split_part(t, ':', 2);
    t := split_part(t, ':', 1);
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;

    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L AND cmd IN (''INSERT'',''UPDATE'',''DELETE'',''ALL'')', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;

    -- SELECT reste public (déjà en place, vitrine/classement) — non touché.
    EXECUTE format($f$
      CREATE POLICY "%1$s_owner_write" ON public.%1$I
        FOR ALL USING ((auth.jwt() ->> 'sub') = %2$I)
        WITH CHECK ((auth.jwt() ->> 'sub') = %2$I)
    $f$, t, col);
  END LOOP;
END $$;

-- ── balades_ludiques_points (rattachée au créateur du parcours parent) ────
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'balades_ludiques_points' AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.balades_ludiques_points', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "balades_ludiques_points_owner_write" ON balades_ludiques_points
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM balades_ludiques b
      WHERE b.id = balades_ludiques_points.balade_id AND b.createur_uid = (auth.jwt() ->> 'sub')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM balades_ludiques b
      WHERE b.id = balades_ludiques_points.balade_id AND b.createur_uid = (auth.jwt() ->> 'sub')
    )
  );

-- ── balades_ludiques_progressions (le joueur lui-même) ────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'balades_ludiques_progressions' AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.balades_ludiques_progressions', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "balades_ludiques_progressions_owner_write" ON balades_ludiques_progressions
  FOR ALL USING ((auth.jwt() ->> 'sub') = joueur_uid)
  WITH CHECK ((auth.jwt() ->> 'sub') = joueur_uid);

-- ── balades_ludiques_validations (rattachée à la progression du joueur) ───
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'balades_ludiques_validations' AND cmd IN ('INSERT','UPDATE','DELETE','ALL')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.balades_ludiques_validations', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "balades_ludiques_validations_owner_write" ON balades_ludiques_validations
  FOR ALL USING ((auth.jwt() ->> 'sub') = joueur_uid)
  WITH CHECK ((auth.jwt() ->> 'sub') = joueur_uid);

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('admin_alerts','activity_log','balades_ludiques','balades_ludiques_points','balades_ludiques_progressions','balades_ludiques_validations','balades_ludiques_avis','balades_ludiques_favoris','badges_obtenus','joueurs_xp')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- CREATE POLICY "admin_alerts_all" ON admin_alerts USING (true) WITH CHECK (true);
-- ALTER TABLE activity_log DISABLE ROW LEVEL SECURITY;
-- DROP POLICY IF EXISTS "balades_ludiques_owner_write" ON balades_ludiques;
-- CREATE POLICY "bl_insert" ON balades_ludiques FOR INSERT WITH CHECK (createur_uid IS NOT NULL);
-- CREATE POLICY "bl_update" ON balades_ludiques FOR UPDATE USING (true);
-- CREATE POLICY "bl_delete" ON balades_ludiques FOR DELETE USING (true);
-- DROP POLICY IF EXISTS "balades_ludiques_points_owner_write" ON balades_ludiques_points;
-- CREATE POLICY "blp_insert" ON balades_ludiques_points FOR INSERT WITH CHECK (true);
-- CREATE POLICY "blp_update" ON balades_ludiques_points FOR UPDATE USING (true);
-- CREATE POLICY "blp_delete" ON balades_ludiques_points FOR DELETE USING (true);
-- DROP POLICY IF EXISTS "balades_ludiques_progressions_owner_write" ON balades_ludiques_progressions;
-- CREATE POLICY "blpr_insert" ON balades_ludiques_progressions FOR INSERT WITH CHECK (joueur_uid IS NOT NULL AND joueur_profile_id IS NOT NULL);
-- CREATE POLICY "blpr_update" ON balades_ludiques_progressions FOR UPDATE USING (true);
-- CREATE POLICY "blpr_delete" ON balades_ludiques_progressions FOR DELETE USING (true);
-- DROP POLICY IF EXISTS "balades_ludiques_validations_owner_write" ON balades_ludiques_validations;
-- CREATE POLICY "blv_insert" ON balades_ludiques_validations FOR INSERT WITH CHECK (joueur_uid IS NOT NULL);
-- CREATE POLICY "blv_update" ON balades_ludiques_validations FOR UPDATE USING (true);
-- CREATE POLICY "blv_delete" ON balades_ludiques_validations FOR DELETE USING (true);
-- DROP POLICY IF EXISTS "balades_ludiques_avis_owner_write" ON balades_ludiques_avis;
-- CREATE POLICY "bla_insert" ON balades_ludiques_avis FOR INSERT WITH CHECK (user_uid IS NOT NULL AND profile_id IS NOT NULL);
-- CREATE POLICY "bla_update" ON balades_ludiques_avis FOR UPDATE USING (true);
-- CREATE POLICY "bla_delete" ON balades_ludiques_avis FOR DELETE USING (true);
-- DROP POLICY IF EXISTS "balades_ludiques_favoris_owner_write" ON balades_ludiques_favoris;
-- CREATE POLICY "blf_insert" ON balades_ludiques_favoris FOR INSERT WITH CHECK (user_uid IS NOT NULL AND profile_id IS NOT NULL);
-- CREATE POLICY "blf_delete" ON balades_ludiques_favoris FOR DELETE USING (true);
-- DROP POLICY IF EXISTS "badges_obtenus_owner_write" ON badges_obtenus;
-- CREATE POLICY "bo_insert" ON badges_obtenus FOR INSERT WITH CHECK (user_uid IS NOT NULL AND profile_id IS NOT NULL);
-- DROP POLICY IF EXISTS "joueurs_xp_owner_write" ON joueurs_xp;
-- CREATE POLICY "xp_insert" ON joueurs_xp FOR INSERT WITH CHECK (user_uid IS NOT NULL AND profile_id IS NOT NULL);
-- CREATE POLICY "xp_update" ON joueurs_xp FOR UPDATE USING (true);
