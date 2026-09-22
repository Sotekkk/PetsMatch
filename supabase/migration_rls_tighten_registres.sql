-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 11/N : registre_mouvements, registre_sanitaire
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase). Aucune self-référence ni dépendance croisée
-- (leçon des vagues 5 et 6) : uniquement une référence vers
-- elevage_cogerants.
--
-- Modèle retenu : registres légaux (entrées/sorties, actes sanitaires) —
-- chaque mouvement/acte appartient à l'élevage qui l'a enregistré
-- (uid_eleveur). Lors d'une cession, cédant ET acquéreur (s'il est lui-même
-- éleveur) ont chacun leur PROPRE ligne dans registre_mouvements — pas de
-- visibilité croisée nécessaire, même principe que agenda_events (vague
-- 8/N). Propriétaire ou cogérant actif uniquement — pas de notion
-- d'employé (registres légaux, responsabilité du gérant).
--
-- ⚠️ À TESTER après exécution :
--   1. Le registre entrées/sorties et le registre sanitaire s'affichent
--      normalement pour l'éleveur.
--   2. Un cogérant actif voit les mêmes registres pour l'élevage qu'il
--      co-gère.
--   3. Ajouter un mouvement (entrée/sortie) et un acte sanitaire (vaccin,
--      traitement...) fonctionne toujours ; une cession confirmée crée
--      bien les lignes de sortie/entrée correspondantes.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── registre_mouvements ──────────────────────────────────────────────────
ALTER TABLE registre_mouvements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "reg_mvt_allow_all" ON registre_mouvements;
DROP POLICY IF EXISTS "registre_mouvements_owner_or_cogerant" ON registre_mouvements;

CREATE POLICY "registre_mouvements_owner_or_cogerant" ON registre_mouvements
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = registre_mouvements.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = registre_mouvements.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- ── registre_sanitaire ───────────────────────────────────────────────────
ALTER TABLE registre_sanitaire ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "registre_sanitaire_owner_or_cogerant" ON registre_sanitaire;

CREATE POLICY "registre_sanitaire_owner_or_cogerant" ON registre_sanitaire
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = registre_sanitaire.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = registre_sanitaire.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- Vérification
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename IN ('registre_mouvements','registre_sanitaire')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "registre_mouvements_owner_or_cogerant" ON registre_mouvements;
-- CREATE POLICY "reg_mvt_allow_all" ON registre_mouvements FOR ALL USING (true) WITH CHECK (true);
--
-- DROP POLICY IF EXISTS "registre_sanitaire_owner_or_cogerant" ON registre_sanitaire;
-- ALTER TABLE registre_sanitaire DISABLE ROW LEVEL SECURITY;
