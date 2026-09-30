-- Données de test (STAGING uniquement) pour rls_partages_test.js.
-- Création : psql "$STAGING_DB_URL" -v action=creer -f scripts/staging/fixtures_partages.sql
-- Ménage   : psql "$STAGING_DB_URL" -v action=supprimer -f scripts/staging/fixtures_partages.sql
\set ON_ERROR_STOP on
\set animal '''XNH3Bl3ZqpfWB5yShw1e'''
\set album '''00000000-0000-4000-8000-00000000a1b0'''

BEGIN;
DELETE FROM album_photos WHERE album_id = :album;
DELETE FROM album_partage WHERE album_id = :album;
DELETE FROM albums_photo WHERE id = :album;
DELETE FROM education_objectifs WHERE libelle = 'test_rls';
DELETE FROM partage_suivi_education WHERE token LIKE 'tok_%test_rls';
DELETE FROM partage_tokens WHERE token LIKE 'tok_%test_rls';
DELETE FROM partage_animal WHERE token = '11111111-1111-4111-8111-111111111111';
DELETE FROM animal_claims WHERE token LIKE 'tok_%test_rls';
DELETE FROM bloquages WHERE uid = 'RIOWjkshiibFwwJpkSzf2P4kDKH2' AND blocked_uid = 'G59EC6CC61OUFQdVPMmw8e9Gp8v2';
COMMIT;

\if :{?action}
\else
  \set action creer
\endif
SELECT :'action' = 'creer' AS creer \gset
\if :creer
BEGIN;
INSERT INTO albums_photo (id, pro_uid, titre) VALUES (:album, 'G59EC6CC61OUFQdVPMmw8e9Gp8v2', 'test_rls');
INSERT INTO album_photos (album_id, photo_url) VALUES (:album, 'https://exemple.invalid/test_rls.jpg');
INSERT INTO album_partage (album_id, token, expire_at, actif) VALUES
  (:album, 'tok_album_test_rls', now() + interval '1 day', true),
  (:album, 'tok_album_expire_test_rls', now() - interval '1 day', true);
INSERT INTO education_objectifs (pro_uid, animal_id, libelle) VALUES ('G59EC6CC61OUFQdVPMmw8e9Gp8v2', :animal, 'test_rls');
INSERT INTO partage_suivi_education (animal_id, pro_uid, token, expire_at, actif) VALUES
  (:animal, 'G59EC6CC61OUFQdVPMmw8e9Gp8v2', 'tok_suivi_test_rls', now() + interval '1 day', true);
INSERT INTO partage_tokens (animal_id, owner_id, token, expires_at) VALUES
  (:animal, 'xoRHVSob5uTWm3sbl6lKWFuIgKF2', 'tok_vet_test_rls', now() + interval '1 day'),
  (:animal, 'xoRHVSob5uTWm3sbl6lKWFuIgKF2', 'tok_vet_expire_test_rls', now() - interval '1 day');
INSERT INTO partage_animal (animal_id, uid_partageur, token, expire_at, actif) VALUES
  (:animal, 'xoRHVSob5uTWm3sbl6lKWFuIgKF2', '11111111-1111-4111-8111-111111111111', now() + interval '1 day', true);
INSERT INTO animal_claims (animal_id, created_by_uid, token, statut) VALUES
  (:animal, 'xoRHVSob5uTWm3sbl6lKWFuIgKF2', 'tok_claim_test_rls', 'en_attente');
COMMIT;
\echo 'données de test créées'
\else
\echo 'données de test supprimées'
\endif
