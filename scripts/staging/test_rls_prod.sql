-- Vérification RLS en PROD après migration — chaque cas dans une
-- transaction ANNULÉE (aucune trace). Les jetons Firebase arrivent en rôle
-- anon : identité = claim sub ; lien secret = en-tête x-pm-token.
-- Usage : psql "$PROD_DB_URL" -f scripts/staging/test_rls_prod.sql
-- Chaque ligne affiche « attendu → obtenu ».
\set QUIET on
\pset footer off
\pset tuples_only on

-- Identifiants pris dans la base (aucune donnée affichée).
SELECT id AS conv, participants->>0 AS conv_membre FROM conversations
WHERE jsonb_array_length(participants) >= 2 LIMIT 1 \gset
SELECT id AS facture, token AS facture_token FROM factures WHERE token IS NOT NULL LIMIT 1 \gset
SELECT id AS profil, uid AS profil_uid FROM user_profiles LIMIT 1 \gset

\echo '── Non connecté'
BEGIN; SET LOCAL ROLE anon; SELECT set_config('request.jwt.claims', '{}', true) \gset x_
SELECT '   messages visibles (0)            → ' || count(*) FROM messages;
SELECT '   conversations visibles (0)       → ' || count(*) FROM conversations;
SELECT '   rdv visibles (0)                 → ' || count(*) FROM rdv;
SELECT '   agenda visible (0)               → ' || count(*) FROM agenda_events;
SELECT '   notifications visibles (0)       → ' || count(*) FROM notifications;
SELECT '   factures visibles (0)            → ' || count(*) FROM factures;
SELECT '   cessions visibles (0)            → ' || count(*) FROM cessions;
SELECT '   tokens véto visibles (0)         → ' || count(*) FROM partage_tokens;
SELECT '   registre mouvements visible (0)  → ' || count(*) FROM registre_mouvements;
SELECT '   profils visibles (>0, publics)   → ' || count(*) FROM user_profiles;
WITH u AS (UPDATE user_profiles SET description = description WHERE id = :'profil' RETURNING 1)
SELECT '   modifie un profil (0)            → ' || count(*) FROM u;
ROLLBACK;

\echo '── Lien secret (facture ouverte par son lien, sans compte)'
BEGIN; SET LOCAL ROLE anon; SELECT set_config('request.jwt.claims', '{}', true) \gset x_
SELECT set_config('request.headers', json_build_object('x-pm-token', :'facture_token')::text, true) \gset x_
SELECT '   factures visibles avec le lien (1) → ' || count(*) FROM factures;
ROLLBACK;

\echo '── Participant d''une conversation'
BEGIN; SET LOCAL ROLE anon; SELECT set_config('request.jwt.claims', json_build_object('sub', :'conv_membre')::text, true) \gset x_
SELECT '   voit sa conversation (1)         → ' || count(*) FROM conversations WHERE id = :'conv';
SELECT '   voit ses messages (>0 si messages) → ' || count(*) FROM messages WHERE conversation_id = :'conv';
ROLLBACK;

\echo '── Propriétaire d''un profil'
BEGIN; SET LOCAL ROLE anon; SELECT set_config('request.jwt.claims', json_build_object('sub', :'profil_uid')::text, true) \gset x_
WITH u AS (UPDATE user_profiles SET description = description WHERE id = :'profil' RETURNING 1)
SELECT '   modifie son profil (1)           → ' || count(*) FROM u;
ROLLBACK;
