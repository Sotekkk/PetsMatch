-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 26/N : avis_pro
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- USING(true) — n'importe qui pouvait créer un faux avis au nom d'un
-- autre client, ou modifier/supprimer l'avis de quelqu'un d'autre sur un
-- profil pro. Modèle : lecture publique (avis affichés sur la fiche
-- publique du pro), écriture réservée au client auteur de l'avis.
--
-- ⚠️ À TESTER après exécution :
--   1. Les avis sur un profil pro (note moyenne, liste) s'affichent
--      normalement pour tout le monde.
--   2. Laisser un avis après une prestation fonctionne pour le client.
--   3. Modifier/supprimer son propre avis fonctionne toujours.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "avis_pro_all" ON avis_pro;

CREATE POLICY "avis_pro_select" ON avis_pro FOR SELECT USING (true);

CREATE POLICY "avis_pro_insert" ON avis_pro
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = client_uid);

CREATE POLICY "avis_pro_update" ON avis_pro
  FOR UPDATE USING ((auth.jwt() ->> 'sub') = client_uid)
  WITH CHECK ((auth.jwt() ->> 'sub') = client_uid);

CREATE POLICY "avis_pro_delete" ON avis_pro
  FOR DELETE USING ((auth.jwt() ->> 'sub') = client_uid);

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename = 'avis_pro'
ORDER BY cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "avis_pro_select" ON avis_pro;
-- DROP POLICY IF EXISTS "avis_pro_insert" ON avis_pro;
-- DROP POLICY IF EXISTS "avis_pro_update" ON avis_pro;
-- DROP POLICY IF EXISTS "avis_pro_delete" ON avis_pro;
-- CREATE POLICY "avis_pro_all" ON avis_pro FOR ALL USING (true);
