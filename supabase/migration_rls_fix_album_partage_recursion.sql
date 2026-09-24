-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — correctif vague 36/N : récursion infinie album_partage ↔ albums_photo
-- ══════════════════════════════════════════════════════════════════════════
-- Erreur en conditions réelles : "infinite recursion detected in policy for
-- relation album_partage" sur toute lecture de album_partage / albums_photo
-- / album_photos.
--
-- Cause : "album_partage_write" était FOR ALL (donc aussi appliquée aux
-- SELECT, combinée en OR avec "album_partage_select") et référence
-- albums_photo ; albums_photo_select référence à son tour album_partage.
-- Résultat : lire album_partage évalue album_partage_write, qui lit
-- albums_photo, qui évalue albums_photo_select, qui relit album_partage →
-- boucle. Corrigé en limitant la policy d'écriture à INSERT/UPDATE/DELETE
-- uniquement (jamais évaluée pour un SELECT).
-- ══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "album_partage_write" ON public.album_partage;

CREATE POLICY "album_partage_insert" ON album_partage
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM albums_photo a
      WHERE a.id = album_partage.album_id
        AND (
          a.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = a.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    )
  );
CREATE POLICY "album_partage_update" ON album_partage
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM albums_photo a
      WHERE a.id = album_partage.album_id
        AND (
          a.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = a.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM albums_photo a
      WHERE a.id = album_partage.album_id
        AND (
          a.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = a.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    )
  );
CREATE POLICY "album_partage_delete" ON album_partage
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM albums_photo a
      WHERE a.id = album_partage.album_id
        AND (
          a.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = a.pro_uid AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
        )
    )
  );

-- Vérification — ne doit lister QUE 4 policies (select + insert + update + delete).
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename = 'album_partage'
ORDER BY cmd;
