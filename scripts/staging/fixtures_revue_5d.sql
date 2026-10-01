-- Données de test (STAGING uniquement) pour rls_revue_5d_test.js.
-- Création : psql "$STAGING_DB_URL" -v action=creer -f scripts/staging/fixtures_revue_5d.sql
-- Ménage   : psql "$STAGING_DB_URL" -v action=supprimer -f scripts/staging/fixtures_revue_5d.sql
\set ON_ERROR_STOP on
\set balade '''00000000-0000-4000-8000-0000005d0b01'''

BEGIN;
DELETE FROM balades_ludiques_points WHERE balade_id = :balade;
DELETE FROM balades_ludiques WHERE id = :balade;
DELETE FROM tests_genetiques WHERE notes = 'test_rls';
COMMIT;

\if :{?action}
\else
  \set action creer
\endif
SELECT :'action' = 'creer' AS creer \gset
\if :creer
BEGIN;
-- animal privé (propriétaire WQvZ…, non admin) et reproducteur public
INSERT INTO tests_genetiques (animal_id, nom, resultat, notes) VALUES
  ('1786093435841', 'Test privé', 'clair', 'test_rls'),
  ('XNH3Bl3ZqpfWB5yShw1e', 'Test reproducteur public', 'porteur', 'test_rls');
INSERT INTO balades_ludiques (id, createur_uid, titre, lat_depart, lng_depart)
  VALUES (:balade, 'G59EC6CC61OUFQdVPMmw8e9Gp8v2', 'test_rls', 45.0, 5.0);
INSERT INTO balades_ludiques_points (id, balade_id, ordre, titre, lat, lng, type_defi, question_texte, question_reponse, qr_code_value) VALUES
  ('00000000-0000-4000-8000-0000005d0b02', :balade, 1, 'Question', 45.0, 5.0, 'question', 'Couleur du ciel ?', 'Bleu', NULL),
  ('00000000-0000-4000-8000-0000005d0b03', :balade, 2, 'QR', 45.0, 5.0, 'qr_code', NULL, NULL, 'PM-QR-TEST');
COMMIT;
\echo 'données de test créées'
\else
\echo 'données de test supprimées'
\endif
