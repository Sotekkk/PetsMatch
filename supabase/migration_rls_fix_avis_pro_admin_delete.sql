-- ══════════════════════════════════════════════════════════════════════════
-- Correctif : l'admin doit pouvoir supprimer un avis suite à une contestation
-- ══════════════════════════════════════════════════════════════════════════
-- Oubli de la migration précédente (avis_pro_eligibilite_contestation) :
-- avis_pro_delete ne laissait que l'auteur du client supprimer son propre
-- avis — l'admin (back-office « Avis contestés ») ne pouvait pas supprimer
-- l'avis d'un tiers suite à une contestation acceptée.
-- ══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "avis_pro_delete" ON avis_pro;
CREATE POLICY "avis_pro_delete" ON avis_pro
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = client_uid
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename = 'avis_pro'
ORDER BY cmd;
