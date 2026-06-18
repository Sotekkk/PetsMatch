-- ─────────────────────────────────────────────────────────────────────────────
-- Fix RLS tables inventaire : même pattern que users_rls
-- L'app utilise Firebase Auth → auth.uid() = null → on autorise anon
-- ─────────────────────────────────────────────────────────────────────────────

-- ── inventaire_items ─────────────────────────────────────────────────────────
ALTER TABLE inventaire_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "inventaire_items_anon_all" ON inventaire_items;
CREATE POLICY "inventaire_items_anon_all" ON inventaire_items
  FOR ALL USING (true) WITH CHECK (true);

-- ── inventaire_mouvements ────────────────────────────────────────────────────
ALTER TABLE inventaire_mouvements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "inventaire_mouvements_anon_all" ON inventaire_mouvements;
CREATE POLICY "inventaire_mouvements_anon_all" ON inventaire_mouvements
  FOR ALL USING (true) WITH CHECK (true);
