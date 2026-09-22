-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 6/N : animal_access, likes, favoris
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase). Attention self-référence (leçon de la vague 5) :
-- aucune des policies ci-dessous ne se relit elle-même, seulement des
-- tables tierces (animaux, elevage_cogerants, user_profiles) — pas de risque
-- de récursion infinie ici.
--
-- Modèle retenu pour animal_access (accès pro délégué : véto, pension,
-- garde, éducation, maréchal-ferrant...) :
--   - SELECT/UPDATE/DELETE : le pro concerné (pro_profile_id → son uid) OU
--     le propriétaire de l'animal (uid_eleveur/uid_proprietaire) OU un
--     cogérant actif du propriétaire (approuver/révoquer un accès pour
--     l'élevage qu'il co-gère).
--   - INSERT : mêmes rôles — couvre à la fois "le propriétaire accorde un
--     accès" et "le pro demande lui-même un accès" (statut pending/
--     write_requested, cf. migration_animal_access_write_states.sql).
--
-- Modèle retenu pour likes / favoris (annonces) — pas de notion de
-- cogérance ici, ce sont des interactions personnelles d'un compte :
--   - SELECT : public (nécessaire pour afficher un compteur "❤️ 12" sur une
--     annonce sans exposer d'info sensible — liker une annonce n'est pas une
--     donnée privée comme un message).
--   - INSERT / DELETE : uniquement son propre like/favori (user_uid).
--
-- ⚠️ À TESTER après exécution :
--   1. Un vétérinaire avec un accès actif voit toujours la fiche/carnet de
--      santé de l'animal ; une demande d'accès (pet-sitter) fonctionne.
--   2. Le propriétaire (et un cogérant actif) peut approuver/révoquer un
--      accès pro depuis la fiche animal.
--   3. Liker / mettre en favori une annonce fonctionne ; le compteur de
--      likes s'affiche toujours sur une annonce publique.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── animal_access ────────────────────────────────────────────────────────
ALTER TABLE animal_access ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "animal_access_anon" ON animal_access;
DROP POLICY IF EXISTS "animal_access_related_select" ON animal_access;
DROP POLICY IF EXISTS "animal_access_related_insert" ON animal_access;
DROP POLICY IF EXISTS "animal_access_related_update" ON animal_access;
DROP POLICY IF EXISTS "animal_access_related_delete" ON animal_access;

CREATE POLICY "animal_access_related_select" ON animal_access
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM user_profiles up
      WHERE up.id = animal_access.pro_profile_id AND up.uid = (auth.jwt() ->> 'sub')
    )
    OR EXISTS (
      SELECT 1 FROM animaux a
      WHERE a.id = animal_access.animal_id
        AND (
          a.uid_eleveur = (auth.jwt() ->> 'sub')
          OR a.uid_proprietaire = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = a.uid_eleveur
              AND c.uid_cogerant = (auth.jwt() ->> 'sub')
              AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  );

CREATE POLICY "animal_access_related_insert" ON animal_access
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles up
      WHERE up.id = animal_access.pro_profile_id AND up.uid = (auth.jwt() ->> 'sub')
    )
    OR EXISTS (
      SELECT 1 FROM animaux a
      WHERE a.id = animal_access.animal_id
        AND (
          a.uid_eleveur = (auth.jwt() ->> 'sub')
          OR a.uid_proprietaire = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = a.uid_eleveur
              AND c.uid_cogerant = (auth.jwt() ->> 'sub')
              AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  );

CREATE POLICY "animal_access_related_update" ON animal_access
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM user_profiles up
      WHERE up.id = animal_access.pro_profile_id AND up.uid = (auth.jwt() ->> 'sub')
    )
    OR EXISTS (
      SELECT 1 FROM animaux a
      WHERE a.id = animal_access.animal_id
        AND (
          a.uid_eleveur = (auth.jwt() ->> 'sub')
          OR a.uid_proprietaire = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = a.uid_eleveur
              AND c.uid_cogerant = (auth.jwt() ->> 'sub')
              AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  );

CREATE POLICY "animal_access_related_delete" ON animal_access
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM user_profiles up
      WHERE up.id = animal_access.pro_profile_id AND up.uid = (auth.jwt() ->> 'sub')
    )
    OR EXISTS (
      SELECT 1 FROM animaux a
      WHERE a.id = animal_access.animal_id
        AND (
          a.uid_eleveur = (auth.jwt() ->> 'sub')
          OR a.uid_proprietaire = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = a.uid_eleveur
              AND c.uid_cogerant = (auth.jwt() ->> 'sub')
              AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  );

-- ── likes ────────────────────────────────────────────────────────────────
ALTER TABLE likes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "likes_all" ON likes;
DROP POLICY IF EXISTS "likes_public_read" ON likes;
DROP POLICY IF EXISTS "likes_own_write" ON likes;

CREATE POLICY "likes_public_read" ON likes FOR SELECT USING (true);
CREATE POLICY "likes_own_write" ON likes
  FOR ALL
  USING (user_uid = (auth.jwt() ->> 'sub'))
  WITH CHECK (user_uid = (auth.jwt() ->> 'sub'));

-- ── favoris ──────────────────────────────────────────────────────────────
ALTER TABLE favoris ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "favoris_all" ON favoris;
DROP POLICY IF EXISTS "favoris_public_read" ON favoris;
DROP POLICY IF EXISTS "favoris_own_write" ON favoris;

CREATE POLICY "favoris_public_read" ON favoris FOR SELECT USING (true);
CREATE POLICY "favoris_own_write" ON favoris
  FOR ALL
  USING (user_uid = (auth.jwt() ->> 'sub'))
  WITH CHECK (user_uid = (auth.jwt() ->> 'sub'));

-- Vérification
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename IN ('animal_access','likes','favoris')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "animal_access_related_select" ON animal_access;
-- DROP POLICY IF EXISTS "animal_access_related_insert" ON animal_access;
-- DROP POLICY IF EXISTS "animal_access_related_update" ON animal_access;
-- DROP POLICY IF EXISTS "animal_access_related_delete" ON animal_access;
-- CREATE POLICY "animal_access_anon" ON animal_access FOR ALL USING (true) WITH CHECK (true);
--
-- DROP POLICY IF EXISTS "likes_public_read" ON likes;
-- DROP POLICY IF EXISTS "likes_own_write" ON likes;
-- CREATE POLICY "likes_all" ON likes FOR ALL USING (true) WITH CHECK (true);
--
-- DROP POLICY IF EXISTS "favoris_public_read" ON favoris;
-- DROP POLICY IF EXISTS "favoris_own_write" ON favoris;
-- CREATE POLICY "favoris_all" ON favoris FOR ALL USING (true) WITH CHECK (true);
