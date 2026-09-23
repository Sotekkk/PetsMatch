-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 12/N : rdv
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase). Aucune self-référence ni dépendance croisée
-- (leçon des vagues 5 et 6) : uniquement une référence vers
-- elevage_cogerants.
--
-- Contrairement à agenda_events (vague 8/N, une ligne par partie), rdv est
-- UNE SEULE ligne partagée entre le pro (pro_uid) et son client (client_uid)
-- — les deux doivent pouvoir la lire/modifier/annuler (confirmé : le client
-- peut supprimer sa propre demande de RDV depuis mes-rdv/page.tsx).
--
-- Modèle retenu : le pro (pro_uid), le client (client_uid), OU un cogérant
-- actif du pro (si le pro est un profil élevage co-géré) — pour
-- SELECT/INSERT/UPDATE/DELETE, identique sur les quatre.
--
-- ⚠️ À TESTER après exécution :
--   1. "Mes RDV" (particulier) et l'agenda pro s'affichent normalement.
--   2. Prendre un RDV, le confirmer/modifier côté pro, l'annuler côté
--      client fonctionnent toujours.
--   3. Un cogérant actif voit et gère les RDV du profil pro qu'il co-gère.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

ALTER TABLE rdv ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "rdv_related_select" ON rdv;
DROP POLICY IF EXISTS "rdv_related_insert" ON rdv;
DROP POLICY IF EXISTS "rdv_related_update" ON rdv;
DROP POLICY IF EXISTS "rdv_related_delete" ON rdv;

CREATE POLICY "rdv_related_select" ON rdv
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR (auth.jwt() ->> 'sub') = client_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = rdv.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "rdv_related_insert" ON rdv
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR (auth.jwt() ->> 'sub') = client_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = rdv.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "rdv_related_update" ON rdv
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR (auth.jwt() ->> 'sub') = client_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = rdv.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "rdv_related_delete" ON rdv
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR (auth.jwt() ->> 'sub') = client_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = rdv.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- Vérification
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'rdv'
ORDER BY cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "rdv_related_select" ON rdv;
-- DROP POLICY IF EXISTS "rdv_related_insert" ON rdv;
-- DROP POLICY IF EXISTS "rdv_related_update" ON rdv;
-- DROP POLICY IF EXISTS "rdv_related_delete" ON rdv;
-- ALTER TABLE rdv DISABLE ROW LEVEL SECURITY;
