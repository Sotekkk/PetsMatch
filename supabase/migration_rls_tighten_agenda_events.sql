-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 8/N : agenda_events
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase). Aucune self-référence ni dépendance croisée
-- (leçon des vagues 5 et 6) : uniquement une référence vers
-- elevage_cogerants, déjà indépendante.
--
-- Modèle retenu : agenda_events sert à la fois de rappels personnels
-- (particulier, pro) et d'agenda partagé élevage. Propriétaire (uid) OU
-- cogérant actif du propriétaire — pas de notion d'employé ici (les tâches
-- assignées aux employés vivent dans taches_elevage/plan_taches, déjà
-- traités en vague 7/N ; agenda_events est la vue calendrier qui les
-- reflète, mais reste elle-même propriété de l'élevage).
--
-- ⚠️ À TESTER après exécution :
--   1. L'agenda (RDV, rappels, événements) s'affiche normalement pour un
--      compte particulier, un compte pro (RDV), et un compte éleveur.
--   2. Un cogérant actif voit l'agenda de l'élevage qu'il co-gère.
--   3. Créer/modifier/supprimer un événement d'agenda fonctionne toujours
--      (RDV, rappel de vaccin, chaleurs, tâche...).
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

ALTER TABLE agenda_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "agenda_events_related_select" ON agenda_events;
DROP POLICY IF EXISTS "agenda_events_related_insert" ON agenda_events;
DROP POLICY IF EXISTS "agenda_events_related_update" ON agenda_events;
DROP POLICY IF EXISTS "agenda_events_related_delete" ON agenda_events;

CREATE POLICY "agenda_events_related_select" ON agenda_events
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = agenda_events.uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "agenda_events_related_insert" ON agenda_events
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = agenda_events.uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "agenda_events_related_update" ON agenda_events
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = agenda_events.uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "agenda_events_related_delete" ON agenda_events
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = agenda_events.uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- Vérification
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'agenda_events'
ORDER BY cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "agenda_events_related_select" ON agenda_events;
-- DROP POLICY IF EXISTS "agenda_events_related_insert" ON agenda_events;
-- DROP POLICY IF EXISTS "agenda_events_related_update" ON agenda_events;
-- DROP POLICY IF EXISTS "agenda_events_related_delete" ON agenda_events;
-- ALTER TABLE agenda_events DISABLE ROW LEVEL SECURITY;
