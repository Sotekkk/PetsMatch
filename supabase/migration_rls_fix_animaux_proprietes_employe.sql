-- ══════════════════════════════════════════════════════════════════════════
-- animaux_proprietes — trou employé (même famille que tous les fix
-- employé de cette session : migration_rls_fix_employe_write_animaux.sql,
-- migration_rls_fix_employe_pension_protocoles.sql,
-- migration_rls_fix_onboarding_progress_cogerant.sql)
-- ══════════════════════════════════════════════════════════════════════════
-- La policy SELECT de `animaux_proprietes` (migration_rls_tighten_animaux.sql,
-- vague 5/N) couvre uid_proprio / cogérant du proprio / propriétaire
-- principal courant de l'animal — mais PAS un employé actif de uid_proprio,
-- alors que la policy SELECT de `animaux` (même fichier, juste au-dessus)
-- couvre bien ce cas. Conséquence concrète : "Mes Employeurs" → onglet
-- 🐾 Animaux (qui liste les animaux confiés via animaux_proprietes,
-- profile_id_proprio = profil de l'employeur — cas pension/famille
-- d'accueil) renvoie 0 animal pour un employé, même quand des lignes
-- existent réellement.
--
-- Ajout de la même branche employé que `animaux`, SELECT uniquement — la
-- gestion des co-propriétaires (ajouter/retirer, INSERT/UPDATE/DELETE) reste
-- réservée au propriétaire/cogérant/propriétaire principal, inchangée.
--
-- ⚠️ À TESTER après exécution :
--   1. Le propriétaire, un cogérant actif, et le propriétaire principal
--      d'un animal continuent de voir/gérer les co-propriétaires normalement.
--   2. Un employé actif voit maintenant les animaux confiés à son employeur
--      via animaux_proprietes dans "Mes Employeurs" → 🐾 Animaux.
--   3. Un employé ne peut toujours PAS ajouter/retirer un co-propriétaire.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "ap_owner_or_cogerant_or_principal_select" ON animaux_proprietes;

CREATE POLICY "ap_owner_or_cogerant_or_principal_or_employe_select" ON animaux_proprietes
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = uid_proprio
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = animaux_proprietes.uid_proprio
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR EXISTS (
      SELECT 1 FROM employes e
      WHERE e.uid_eleveur = animaux_proprietes.uid_proprio
        AND e.uid_employe = (auth.jwt() ->> 'sub')
        AND e.actif = true
    )
    OR public.is_principal_owner_or_cogerant(animaux_proprietes.animal_id, (auth.jwt() ->> 'sub'))
  );

-- Vérification
SELECT policyname, cmd FROM pg_policies WHERE tablename = 'animaux_proprietes' ORDER BY cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "ap_owner_or_cogerant_or_principal_or_employe_select" ON animaux_proprietes;
-- CREATE POLICY "ap_owner_or_cogerant_or_principal_select" ON animaux_proprietes
--   FOR SELECT USING (
--     (auth.jwt() ->> 'sub') = uid_proprio
--     OR EXISTS (
--       SELECT 1 FROM elevage_cogerants c
--       WHERE c.uid_gerant = animaux_proprietes.uid_proprio
--         AND c.uid_cogerant = (auth.jwt() ->> 'sub')
--         AND c.statut = 'actif' AND c.date_fin IS NULL
--     )
--     OR public.is_principal_owner_or_cogerant(animaux_proprietes.animal_id, (auth.jwt() ->> 'sub'))
--   );
