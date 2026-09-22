-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 10/N : annonces
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase). Aucune self-référence ni dépendance croisée
-- (leçon des vagues 5 et 6) : uniquement une référence vers
-- elevage_cogerants.
--
-- Modèle retenu : les annonces sont PAR NATURE publiques (annuaire/vitrine
-- consultée par n'importe qui, connecté ou non) — la lecture reste donc
-- permissive, INCHANGÉE. Seule l'écriture change : réservée au propriétaire
-- (uid_eleveur) ou à un cogérant actif de l'élevage.
--
-- ⚠️ Exception : le compteur de vues (annonce_detail_page.dart) est
-- incrémenté par N'IMPORTE QUEL VISITEUR qui n'est pas le propriétaire —
-- un UPDATE direct sur la ligne échouerait silencieusement sous la policy
-- ci-dessous. Passe donc par une fonction SECURITY DEFINER dédiée
-- (increment_annonce_vues), seule exception à "écriture réservée au
-- propriétaire" pour cette table, volontairement limitée à cette seule
-- colonne.
--
-- ⚠️ À TESTER après exécution :
--   1. Le fil d'annonces / la recherche s'affichent normalement, y compris
--      déconnecté.
--   2. Créer, modifier, mettre en pause, supprimer une annonce fonctionne
--      pour le propriétaire.
--   3. Un cogérant actif peut créer/modifier/supprimer une annonce pour
--      l'élevage qu'il co-gère.
--   4. Consulter une annonce depuis un autre compte incrémente bien son
--      compteur de vues.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.increment_annonce_vues(p_annonce_id TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE annonces SET vues = COALESCE(vues, 0) + 1 WHERE id = p_annonce_id;
$$;
GRANT EXECUTE ON FUNCTION public.increment_annonce_vues(TEXT) TO anon, authenticated;

ALTER TABLE annonces ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "firebase_allow_all" ON annonces;
DROP POLICY IF EXISTS "annonces_public_read" ON annonces;
DROP POLICY IF EXISTS "annonces_owner_or_cogerant_insert" ON annonces;
DROP POLICY IF EXISTS "annonces_owner_or_cogerant_update" ON annonces;
DROP POLICY IF EXISTS "annonces_owner_or_cogerant_delete" ON annonces;

CREATE POLICY "annonces_public_read" ON annonces
  FOR SELECT USING (true);

CREATE POLICY "annonces_owner_or_cogerant_insert" ON annonces
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = annonces.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "annonces_owner_or_cogerant_update" ON annonces
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = annonces.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "annonces_owner_or_cogerant_delete" ON annonces
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = annonces.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- Vérification
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'annonces'
ORDER BY cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "annonces_public_read" ON annonces;
-- DROP POLICY IF EXISTS "annonces_owner_or_cogerant_insert" ON annonces;
-- DROP POLICY IF EXISTS "annonces_owner_or_cogerant_update" ON annonces;
-- DROP POLICY IF EXISTS "annonces_owner_or_cogerant_delete" ON annonces;
-- CREATE POLICY "firebase_allow_all" ON annonces FOR ALL USING (true) WITH CHECK (true);
-- DROP FUNCTION IF EXISTS public.increment_annonce_vues(TEXT);
