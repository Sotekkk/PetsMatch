-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — correctif vague 43/N : cessions, oubli de uid_acquereur
-- ══════════════════════════════════════════════════════════════════════════
-- La vague 43/N verrouillait l'écriture de `cessions` à
-- uid_eleveur/cogérant, en s'appuyant sur la nouvelle route API
-- api/cessions/sign pour la signature anonyme via lien. Oubli trouvé en
-- auditant documents_animaux (vague 44/N) : l'acquéreur peut AUSSI signer
-- une cession depuis l'appli Flutter, authentifié (pas anonyme, pas
-- l'éleveur) — lib/pages/contrats/contrat_signature_page.dart::
-- _signerCession() écrit directement dans `cessions`, pas via la route API
-- (qui ne sert que le lien web anonyme). La colonne uid_acquereur existe
-- déjà sur cessions (contrairement à documents_animaux) : ajoutée à la
-- policy d'écriture.
-- ══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "cessions_write" ON public.cessions;
CREATE POLICY "cessions_write" ON cessions
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR (auth.jwt() ->> 'sub') = uid_acquereur
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = cessions.uid_eleveur AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR (auth.jwt() ->> 'sub') = uid_acquereur
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = cessions.uid_eleveur AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  );

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename = 'cessions'
ORDER BY cmd;
