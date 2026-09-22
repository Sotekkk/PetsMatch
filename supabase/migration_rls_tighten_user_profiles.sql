-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 1/N : user_profiles
-- ══════════════════════════════════════════════════════════════════════════
-- Contexte : jusqu'ici auth.uid() était toujours NULL (app en Firebase Auth,
-- client Supabase en clé anon seule) → toutes les policies étaient
-- USING(true)/WITH CHECK(true), donc n'importe qui en possession de la clé
-- anon (publique par construction, embarquée dans l'APK et le site) pouvait
-- lire/écrire n'importe quelle ligne via l'API REST Supabase directement,
-- sans passer par l'appli ni par un compte.
--
-- Ce qui a changé : Firebase est maintenant configuré côté Supabase comme
-- fournisseur "Third-Party Auth", et le client (app + site) transmet le
-- token Firebase à chaque requête. Le JWT est donc réellement vérifiable.
--
-- IMPORTANT — ne pas utiliser auth.uid() : cette fonction caste en UUID, et
-- les uid Firebase ne sont pas des UUID (ex. "aB3xY9kLp..."), le cast
-- échouerait. On utilise (auth.jwt() ->> 'sub') à la place, qui lit le
-- claim "sub" du JWT en texte brut — c'est la méthode recommandée par
-- Supabase pour un fournisseur tiers (Firebase).
--
-- Modèle retenu pour user_profiles :
--   - Lecture : publique, inchangée (annuaire des pros, profils publics).
--   - Écriture (INSERT/UPDATE/DELETE) : le propriétaire du profil, PLUS un
--     cogérant actif de l'élevage pour l'UPDATE (elevage_cogerants) — sans
--     cette clause, une cogérante ne pourrait plus éditer le profil élevage
--     du gérant principal (fonctionnalité livrée cette semaine), puisque
--     son propre uid Firebase diffère de celui du gérant.
--   - INSERT/DELETE restent réservés au propriétaire : la création d'un
--     nouveau type de profil et la suppression sont des actions de compte,
--     jamais déléguées à un cogérant dans le code actuel.
--
-- ⚠️ À TESTER après exécution, avant de considérer la migration comme
-- terminée :
--   1. Connexion normale + affichage d'un profil public (annuaire).
--   2. Modification de son propre profil (nom, adresse, etc.).
--   3. Un cogérant actif modifie le profil élevage du gérant (ex. adresse,
--      SIRET) depuis Élevage → Mon Profil.
--   4. Création d'un nouveau profil (ex. ajout d'un profil véto) depuis un
--      compte existant.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "firebase_allow_all"              ON user_profiles;
DROP POLICY IF EXISTS "Public read user_profiles"        ON user_profiles;
DROP POLICY IF EXISTS "Owner can insert user_profiles"    ON user_profiles;
DROP POLICY IF EXISTS "Owner can update user_profiles"    ON user_profiles;
DROP POLICY IF EXISTS "Owner can delete user_profiles"    ON user_profiles;
DROP POLICY IF EXISTS "user_profiles_public_read"                  ON user_profiles;
DROP POLICY IF EXISTS "user_profiles_owner_insert"                 ON user_profiles;
DROP POLICY IF EXISTS "user_profiles_owner_or_cogerant_update"     ON user_profiles;
DROP POLICY IF EXISTS "user_profiles_owner_delete"                 ON user_profiles;

-- Lecture publique — inchangée (annuaire des pros, profils publics).
CREATE POLICY "user_profiles_public_read" ON user_profiles
  FOR SELECT USING (true);

-- Création : uniquement le propriétaire (un cogérant ne crée jamais de
-- nouveau profil pour le compte du gérant dans le code actuel).
CREATE POLICY "user_profiles_owner_insert" ON user_profiles
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = uid);

-- Modification : le propriétaire OU un cogérant actif de cet élevage.
CREATE POLICY "user_profiles_owner_or_cogerant_update" ON user_profiles
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant   = user_profiles.uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut       = 'actif'
        AND c.date_fin IS NULL
    )
  );

-- Suppression : uniquement le propriétaire.
CREATE POLICY "user_profiles_owner_delete" ON user_profiles
  FOR DELETE USING ((auth.jwt() ->> 'sub') = uid);

-- Vérification (affiche les policies actives après exécution)
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'user_profiles'
ORDER BY cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue, exécuter ce bloc pour
-- revenir immédiatement à l'état permissif précédent (aucune perte de
-- données, juste les policies) :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "user_profiles_public_read"              ON user_profiles;
-- DROP POLICY IF EXISTS "user_profiles_owner_insert"              ON user_profiles;
-- DROP POLICY IF EXISTS "user_profiles_owner_or_cogerant_update"  ON user_profiles;
-- DROP POLICY IF EXISTS "user_profiles_owner_delete"              ON user_profiles;
-- CREATE POLICY "firebase_allow_all" ON user_profiles FOR ALL USING (true) WITH CHECK (true);
