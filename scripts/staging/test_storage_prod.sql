-- Tests des policies storage par rôle, en SQL, chaque cas dans une
-- transaction ANNULÉE (utilisable sur la prod sans laisser de trace).
-- Usage : psql "$PROD_DB_URL" -f scripts/staging/test_storage_prod.sql
-- Les jetons Firebase arrivent en rôle anon ; l'identité = claim sub.
\pset footer off
\pset tuples_only on
\set QUIET on

-- Une story existante et son auteur (via le profil du 1er dossier).
SELECT o.name AS story_name, up.uid AS story_uid
FROM storage.objects o JOIN user_profiles up ON up.id::text = (storage.foldername(o.name))[1]
WHERE o.bucket_id = 'stories' LIMIT 1 \gset
SELECT name AS doc_name FROM storage.objects WHERE bucket_id = 'documents' LIMIT 1 \gset

\echo '── Non connecté'
BEGIN; SET LOCAL ROLE anon; SELECT set_config('request.jwt.claims', '{}', true) \gset ignore_
SELECT '   voit des fichiers via l''API (0)          → ' || count(*) FROM storage.objects;
ROLLBACK;
BEGIN; SET LOCAL ROLE anon; SELECT set_config('request.jwt.claims', '{}', true) \gset ignore_
\echo '   dépôt media (attendu : ERREUR RLS) →'
INSERT INTO storage.objects (bucket_id, name) VALUES ('media', 'test_sec/anon.jpg');
ROLLBACK;
BEGIN; SET LOCAL ROLE anon; SELECT set_config('request.jwt.claims', '{}', true) \gset ignore_
SELECT set_config('storage.allow_delete_query', 'true', true) \gset ignore_
WITH d AS (DELETE FROM storage.objects WHERE bucket_id = 'documents' AND name = :'doc_name' RETURNING 1)
SELECT '   supprime un document (0)                  → ' || count(*) FROM d;
ROLLBACK;
BEGIN; SET LOCAL ROLE anon; SELECT set_config('request.jwt.claims', '{}', true) \gset ignore_
SELECT set_config('storage.allow_delete_query', 'true', true) \gset ignore_
WITH d AS (DELETE FROM storage.objects WHERE bucket_id = 'stories' AND name = :'story_name' RETURNING 1)
SELECT '   supprime une story (0)                    → ' || count(*) FROM d;
ROLLBACK;
BEGIN; SET LOCAL ROLE anon; SELECT set_config('request.jwt.claims', '{}', true) \gset ignore_
WITH i AS (INSERT INTO storage.objects (bucket_id, name)
  VALUES ('contrats', 'contrat_5e9284bd-87cb-411a-8b70-f3ea1adb0486_1790770000000.html') RETURNING 1)
SELECT '   dépôt contrat « Finaliser » (1)           → ' || count(*) FROM i;
ROLLBACK;
BEGIN; SET LOCAL ROLE anon; SELECT set_config('request.jwt.claims', '{}', true) \gset ignore_
SELECT '   voit les anciens contrats (0)             → ' || count(*) FROM storage.objects WHERE bucket_id = 'contrats';
ROLLBACK;

\echo '── Natacha (élevage)'
BEGIN; SET LOCAL ROLE anon; SELECT set_config('request.jwt.claims', '{"sub":"YF9kR7jSTObnnw9lVj8gCl031rS2"}', true) \gset ignore_
SELECT '   voit les fichiers hors contrats (>0)       → ' || count(*) FROM storage.objects;
WITH i AS (INSERT INTO storage.objects (bucket_id, name) VALUES ('media', 'test_sec/nat.pdf') RETURNING 1)
SELECT '   dépôt media (1)                           → ' || count(*) FROM i;
WITH u AS (UPDATE storage.objects SET metadata = metadata WHERE bucket_id = 'media' AND name = 'test_sec/nat.pdf' RETURNING 1)
SELECT '   remplacement media (1)                    → ' || count(*) FROM u;
ROLLBACK;

\echo '── Employé IfhR'
BEGIN; SET LOCAL ROLE anon; SELECT set_config('request.jwt.claims', '{"sub":"IfhRVwY55KUXW12lBG4D0bs0V383"}', true) \gset ignore_
WITH i AS (INSERT INTO storage.objects (bucket_id, name) VALUES ('documents', 'test_sec/emp.pdf') RETURNING 1)
SELECT '   dépôt documents (1)                       → ' || count(*) FROM i;
WITH i AS (INSERT INTO storage.objects (bucket_id, name) VALUES ('media', 'test_sec/emp.jpg') RETURNING 1)
SELECT '   dépôt media (1)                           → ' || count(*) FROM i;
ROLLBACK;

\echo '── Stories'
BEGIN; SET LOCAL ROLE anon; SELECT set_config('request.jwt.claims', '{"sub":"PZltNeW1M4cmEmOdRlbvOVmUNyB2"}', true) \gset ignore_
SELECT set_config('storage.allow_delete_query', 'true', true) \gset ignore_
WITH d AS (DELETE FROM storage.objects WHERE bucket_id = 'stories' AND name = :'story_name'
           AND :'story_uid' <> 'PZltNeW1M4cmEmOdRlbvOVmUNyB2' RETURNING 1)
SELECT '   un tiers supprime la story d''un autre (0) → ' || count(*) FROM d;
ROLLBACK;
BEGIN; SET LOCAL ROLE anon; SELECT set_config('request.jwt.claims', json_build_object('sub', :'story_uid')::text, true) \gset ignore_
SELECT set_config('storage.allow_delete_query', 'true', true) \gset ignore_
WITH d AS (DELETE FROM storage.objects WHERE bucket_id = 'stories' AND name = :'story_name' RETURNING 1)
SELECT '   l''auteur supprime sa story (1)            → ' || count(*) FROM d;
ROLLBACK;
BEGIN; SET LOCAL ROLE anon; SELECT set_config('request.jwt.claims', '{"sub":"YF9kR7jSTObnnw9lVj8gCl031rS2"}', true) \gset ignore_
SELECT set_config('storage.allow_delete_query', 'true', true) \gset ignore_
WITH d AS (DELETE FROM storage.objects WHERE bucket_id = 'documents' AND name = :'doc_name' RETURNING 1)
SELECT '   connecté supprime un document (0)         → ' || count(*) FROM d;
ROLLBACK;

\echo '── Contrôle : aucun fichier de test resté'
SELECT '   fichiers test_sec / 1790770000000 (0)      → ' || count(*) FROM storage.objects
WHERE name LIKE 'test_sec/%' OR name LIKE '%1790770000000%';
