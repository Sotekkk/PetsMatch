-- Données de test (STAGING uniquement) pour rls_donnees_privees_test.js.
-- Création : psql "$STAGING_DB_URL" -v action=creer -f scripts/staging/fixtures_donnees_privees.sql
-- Ménage   : psql "$STAGING_DB_URL" -v action=supprimer -f scripts/staging/fixtures_donnees_privees.sql
\set ON_ERROR_STOP on
\set grp '''00000000-0000-4000-8000-0000000c5a01'''
\set post '''00000000-0000-4000-8000-0000000c5a02'''

BEGIN;
DELETE FROM groupe_post_commentaires WHERE post_id = :post;
DELETE FROM groupe_posts WHERE groupe_id = :grp;
DELETE FROM groupes_membres WHERE groupe_id = :grp;
DELETE FROM groupes WHERE id = :grp;
DELETE FROM conversation_reports WHERE reason = 'test_rls';
DELETE FROM promenades_messages WHERE message = 'test_rls';
COMMIT;

\if :{?action}
\else
  \set action creer
\endif
SELECT :'action' = 'creer' AS creer \gset
\if :creer
BEGIN;
INSERT INTO groupes (id, createur_uid, nom, prive) VALUES (:grp, 'G59EC6CC61OUFQdVPMmw8e9Gp8v2', 'test_rls privé', true);
INSERT INTO groupes_membres (groupe_id, user_uid, statut, role) VALUES
  (:grp, 'G59EC6CC61OUFQdVPMmw8e9Gp8v2', 'active', 'admin'),
  (:grp, 'RIOWjkshiibFwwJpkSzf2P4kDKH2', 'active', 'membre');
INSERT INTO groupe_posts (id, groupe_id, auteur_uid, contenu) VALUES (:post, :grp, 'G59EC6CC61OUFQdVPMmw8e9Gp8v2', 'test_rls');
INSERT INTO groupe_post_commentaires (post_id, auteur_uid, contenu) VALUES (:post, 'RIOWjkshiibFwwJpkSzf2P4kDKH2', 'test_rls');
INSERT INTO conversation_reports (conversation_id, reported_by_uid, reason) VALUES
  ('c04e94e4-e46a-49d4-9983-e8adf669a72b', 'RIOWjkshiibFwwJpkSzf2P4kDKH2', 'test_rls');
COMMIT;
\echo 'données de test créées'
\else
\echo 'données de test supprimées'
\endif
