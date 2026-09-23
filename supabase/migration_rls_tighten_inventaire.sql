-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 21/N : inventaire
--   inventaire_items, inventaire_mouvements
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- RLS était explicitement DÉSACTIVÉE sur ces deux tables, avec un
-- commentaire d'origine : « l'app utilise Firebase Auth (pas Supabase
-- Auth) → auth.uid() = null, la sécurité est assurée par le filtrage
-- uid_eleveur côté app » — exactement l'hypothèse fausse corrigée sur
-- tout ce chantier (Third-Party Auth actif depuis, auth.jwt() ->> 'sub'
-- donne le vrai uid).
--
-- Modèle retenu : propriétaire (uid_eleveur) / cogérant actif — accès
-- complet. Employé actif de l'élevage : lecture toujours, écriture
-- seulement avec la permission granulaire 'write_inventaire' (Mes
-- Employés → permissions ; réplique exactement le comportement déjà
-- affiché côté appli : "Voir l'inventaire (lecture seule)" sans elle).
--
-- ⚠️ À TESTER après exécution :
--   1. L'inventaire (articles + mouvements de stock) s'affiche
--      normalement pour l'éleveur, un cogérant actif, ET un employé actif
--      (lecture au minimum).
--   2. Ajouter/modifier un article, enregistrer un mouvement de stock
--      fonctionnent pour l'éleveur/cogérant ET un employé avec la
--      permission "Inventaire" (write_inventaire).
--   3. Un employé SANS cette permission voit l'inventaire en lecture
--      seule (ne peut plus rien modifier).
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.can_access_inventaire(p_uid_eleveur TEXT, p_uid TEXT, p_require_write BOOLEAN DEFAULT false)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT p_uid_eleveur = p_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = p_uid_eleveur
        AND c.uid_cogerant = p_uid AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR EXISTS (
      SELECT 1 FROM employes e
      WHERE e.uid_eleveur = p_uid_eleveur
        AND e.uid_employe = p_uid
        AND e.actif = true
        AND (
          NOT p_require_write
          OR EXISTS (
            SELECT 1 FROM employe_permissions ep
            WHERE ep.eleveur_profile_id = e.eleveur_profile_id
              AND ep.employe_profile_id = e.employe_profile_id
              AND ep.permission IN ('write_inventaire', 'write_animaux')
          )
        )
    );
$$;
GRANT EXECUTE ON FUNCTION public.can_access_inventaire(TEXT, TEXT, BOOLEAN) TO anon, authenticated;

-- ── inventaire_items ───────────────────────────────────────────────────────
ALTER TABLE inventaire_items ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'inventaire_items'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.inventaire_items', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "inventaire_items_select" ON inventaire_items
  FOR SELECT USING (public.can_access_inventaire(uid_eleveur, (auth.jwt() ->> 'sub'), false));

CREATE POLICY "inventaire_items_insert" ON inventaire_items
  FOR INSERT WITH CHECK (public.can_access_inventaire(uid_eleveur, (auth.jwt() ->> 'sub'), true));

CREATE POLICY "inventaire_items_update" ON inventaire_items
  FOR UPDATE USING (public.can_access_inventaire(uid_eleveur, (auth.jwt() ->> 'sub'), true))
  WITH CHECK (public.can_access_inventaire(uid_eleveur, (auth.jwt() ->> 'sub'), true));

CREATE POLICY "inventaire_items_delete" ON inventaire_items
  FOR DELETE USING (public.can_access_inventaire(uid_eleveur, (auth.jwt() ->> 'sub'), true));

-- ── inventaire_mouvements ──────────────────────────────────────────────────
ALTER TABLE inventaire_mouvements ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'inventaire_mouvements'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.inventaire_mouvements', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "inventaire_mouvements_select" ON inventaire_mouvements
  FOR SELECT USING (public.can_access_inventaire(uid_eleveur, (auth.jwt() ->> 'sub'), false));

CREATE POLICY "inventaire_mouvements_insert" ON inventaire_mouvements
  FOR INSERT WITH CHECK (public.can_access_inventaire(uid_eleveur, (auth.jwt() ->> 'sub'), true));

CREATE POLICY "inventaire_mouvements_update" ON inventaire_mouvements
  FOR UPDATE USING (public.can_access_inventaire(uid_eleveur, (auth.jwt() ->> 'sub'), true))
  WITH CHECK (public.can_access_inventaire(uid_eleveur, (auth.jwt() ->> 'sub'), true));

CREATE POLICY "inventaire_mouvements_delete" ON inventaire_mouvements
  FOR DELETE USING (public.can_access_inventaire(uid_eleveur, (auth.jwt() ->> 'sub'), true));

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('inventaire_items','inventaire_mouvements')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('inventaire_items','inventaire_mouvements')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- ALTER TABLE inventaire_items      DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE inventaire_mouvements DISABLE ROW LEVEL SECURITY;
-- DROP FUNCTION IF EXISTS public.can_access_inventaire(TEXT, TEXT, BOOLEAN);
