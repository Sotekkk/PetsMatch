-- ══════════════════════════════════════════════════════════════════════════
-- onboarding_progress — trou cogérant (même famille que les bugs employé
-- déjà corrigés : migration_rls_fix_employe_write_animaux.sql,
-- migration_rls_fix_employe_pension_protocoles.sql)
-- ══════════════════════════════════════════════════════════════════════════
-- La policy d'origine (migration_rls_tighten_genetique_factures_onboarding.sql,
-- vague 31/N) ne vérifiait QUE up.uid = (auth.jwt()->>'sub') — le vrai
-- propriétaire du profil. Un cogérant actif accédant au MÊME profil élevage
-- (elevage_cogerants, même profile_id « emprunté tel quel » — cf.
-- auth-context.tsx / ProfileService côté appli) a un uid différent : la
-- ligne onboarding_progress existante (déjà complétée par le gérant) lui
-- était invisible → getProgress() renvoyait null → shouldAutoLaunch()
-- relançait l'onboarding à chaque connexion, alors que le profil élevage
-- est déjà pleinement configuré. Signalé : Ambre (cogérante) voit
-- l'onboarding sur l'élevage "Pomsky de la Luna" de sa mère.
--
-- ⚠️ À TESTER après exécution :
--   1. Le gérant (propriétaire du profil) continue de voir/modifier sa
--      propre progression d'onboarding normalement.
--   2. Un cogérant actif du même élevage NE VOIT PLUS l'onboarding se
--      relancer sur ce profil (la ligne existante devient visible).
--   3. Un cogérant qui termine lui-même une étape (markStepCompleted) le
--      fait bien pour le profil élevage partagé (comportement voulu : la
--      progression appartient au PROFIL, pas à qui l'a rempli).
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "onboarding_progress_owner" ON onboarding_progress;

CREATE POLICY "onboarding_progress_owner_or_cogerant" ON onboarding_progress
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM user_profiles up
      WHERE up.id = onboarding_progress.profile_id
        AND (
          up.uid = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = up.uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub')
              AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles up
      WHERE up.id = onboarding_progress.profile_id
        AND (
          up.uid = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = up.uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub')
              AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  );

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename = 'onboarding_progress'
ORDER BY cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "onboarding_progress_owner_or_cogerant" ON onboarding_progress;
-- CREATE POLICY "onboarding_progress_owner" ON onboarding_progress
--   FOR ALL USING (
--     EXISTS (
--       SELECT 1 FROM user_profiles up
--       WHERE up.id = onboarding_progress.profile_id AND up.uid = (auth.jwt() ->> 'sub')
--     )
--   )
--   WITH CHECK (
--     EXISTS (
--       SELECT 1 FROM user_profiles up
--       WHERE up.id = onboarding_progress.profile_id AND up.uid = (auth.jwt() ->> 'sub')
--     )
--   );
