-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 4/N : employes, elevage_cogerants
-- ══════════════════════════════════════════════════════════════════════════
-- Même contexte que les vagues précédentes : (auth.jwt() ->> 'sub') reflète
-- le vrai uid Firebase connecté (Third-Party Auth actif côté Supabase).
--
-- Modèle retenu pour employes :
--   - SELECT : l'employeur (uid_eleveur) OU un cogérant actif de son
--     élevage OU l'employé lui-même (il doit voir ses propres employeurs,
--     page "Mes Employeurs").
--   - INSERT / DELETE : l'employeur ou un cogérant actif uniquement
--     (ajouter/révoquer un employé).
--   - UPDATE : l'employeur, un cogérant actif, OU l'employé lui-même
--     (ex. accepter une invitation, mettre à jour son propre statut).
--
-- Modèle retenu pour elevage_cogerants :
--   - SELECT : le gérant OU le cogérant concerné (les deux parties d'une
--     relation doivent la voir).
--   - INSERT : uniquement le gérant (invite un cogérant).
--   - UPDATE : le gérant (résilier) OU le cogérant (accepter/refuser).
--   - DELETE : uniquement le gérant, et seulement une invitation encore en
--     attente (statut='invite') — une co-gérance active se résilie via
--     date_fin, jamais supprimée (historique conservé, exigence explicite).
--
-- ⚠️ À TESTER après exécution :
--   1. La liste "Mes Employés" s'affiche pour l'éleveur ET pour un cogérant
--      actif (le bug corrigé cette semaine ne doit pas revenir).
--   2. "Mes Employeurs" (vue employé) affiche bien ses employeurs.
--   3. Ajouter / révoquer un employé fonctionne.
--   4. Inviter un cogérant, l'invitation reçue s'affiche côté cogérant,
--      accepter fonctionne, résilier fonctionne, annuler une invitation
--      en attente fonctionne.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── employes ─────────────────────────────────────────────────────────────
ALTER TABLE employes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "employes_anon_select" ON employes;
DROP POLICY IF EXISTS "employes_anon_insert" ON employes;
DROP POLICY IF EXISTS "employes_anon_update" ON employes;
DROP POLICY IF EXISTS "employes_anon_delete" ON employes;
DROP POLICY IF EXISTS "employes_owner_or_cogerant_or_self_select" ON employes;
DROP POLICY IF EXISTS "employes_owner_or_cogerant_insert"          ON employes;
DROP POLICY IF EXISTS "employes_owner_or_cogerant_or_self_update"  ON employes;
DROP POLICY IF EXISTS "employes_owner_or_cogerant_delete"          ON employes;

CREATE POLICY "employes_owner_or_cogerant_or_self_select" ON employes
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR (auth.jwt() ->> 'sub') = uid_employe
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant   = employes.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut       = 'actif'
        AND c.date_fin IS NULL
    )
  );

CREATE POLICY "employes_owner_or_cogerant_insert" ON employes
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant   = employes.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut       = 'actif'
        AND c.date_fin IS NULL
    )
  );

CREATE POLICY "employes_owner_or_cogerant_or_self_update" ON employes
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR (auth.jwt() ->> 'sub') = uid_employe
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant   = employes.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut       = 'actif'
        AND c.date_fin IS NULL
    )
  );

CREATE POLICY "employes_owner_or_cogerant_delete" ON employes
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant   = employes.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut       = 'actif'
        AND c.date_fin IS NULL
    )
  );

-- ── elevage_cogerants ────────────────────────────────────────────────────
ALTER TABLE elevage_cogerants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "firebase_allow_all" ON elevage_cogerants;
DROP POLICY IF EXISTS "cogerants_party_select" ON elevage_cogerants;
DROP POLICY IF EXISTS "cogerants_gerant_insert" ON elevage_cogerants;
DROP POLICY IF EXISTS "cogerants_party_update"  ON elevage_cogerants;
DROP POLICY IF EXISTS "cogerants_gerant_delete_invite" ON elevage_cogerants;

CREATE POLICY "cogerants_party_select" ON elevage_cogerants
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = uid_gerant
    OR (auth.jwt() ->> 'sub') = uid_cogerant
  );

CREATE POLICY "cogerants_gerant_insert" ON elevage_cogerants
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = uid_gerant);

CREATE POLICY "cogerants_party_update" ON elevage_cogerants
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = uid_gerant
    OR (auth.jwt() ->> 'sub') = uid_cogerant
  );

-- Suppression : uniquement le gérant, et seulement une invitation encore en
-- attente — une co-gérance active/passée ne se supprime jamais (date_fin).
CREATE POLICY "cogerants_gerant_delete_invite" ON elevage_cogerants
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = uid_gerant
    AND statut = 'invite'
  );

-- Vérification
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename IN ('employes','elevage_cogerants')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "employes_owner_or_cogerant_or_self_select" ON employes;
-- DROP POLICY IF EXISTS "employes_owner_or_cogerant_insert"          ON employes;
-- DROP POLICY IF EXISTS "employes_owner_or_cogerant_or_self_update"  ON employes;
-- DROP POLICY IF EXISTS "employes_owner_or_cogerant_delete"          ON employes;
-- CREATE POLICY "employes_anon_select" ON employes FOR SELECT USING (true);
-- CREATE POLICY "employes_anon_insert" ON employes FOR INSERT WITH CHECK (true);
-- CREATE POLICY "employes_anon_update" ON employes FOR UPDATE USING (true) WITH CHECK (true);
-- CREATE POLICY "employes_anon_delete" ON employes FOR DELETE USING (true);
--
-- DROP POLICY IF EXISTS "cogerants_party_select" ON elevage_cogerants;
-- DROP POLICY IF EXISTS "cogerants_gerant_insert" ON elevage_cogerants;
-- DROP POLICY IF EXISTS "cogerants_party_update"  ON elevage_cogerants;
-- DROP POLICY IF EXISTS "cogerants_gerant_delete_invite" ON elevage_cogerants;
-- CREATE POLICY "firebase_allow_all" ON elevage_cogerants FOR ALL USING (true) WITH CHECK (true);
