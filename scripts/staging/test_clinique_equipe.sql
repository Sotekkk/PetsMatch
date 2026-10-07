-- Tests RLS « équipe vétérinaire » (migration_clinique_equipe.sql).
-- Tout dans une transaction ANNULÉE : données fictives, aucune trace.
-- Usage : psql "$STAGING_DB_URL" -f scripts/staging/test_clinique_equipe.sql
-- Chaque ligne affiche « attendu → obtenu ».
\set QUIET on
\pset footer off
\pset tuples_only on
\set ON_ERROR_STOP off

-- Profils existants réutilisés comme acteurs (rien n'est affiché d'eux) :
--   clinique = un profil pro ; second profil du même compte si possible
--   employé  = profil particulier d'un autre compte
--   proprio  = profil particulier d'un 3e compte
SELECT id AS clinique, uid AS veto FROM user_profiles
 WHERE profile_type NOT IN ('particulier') ORDER BY created_at LIMIT 1 \gset
SELECT id AS emp_profil, uid AS emp FROM user_profiles
 WHERE profile_type = 'particulier' AND uid <> :'veto' ORDER BY created_at LIMIT 1 \gset
SELECT id AS proprio_profil, uid AS proprio FROM user_profiles
 WHERE profile_type = 'particulier' AND uid NOT IN (:'veto', :'emp') ORDER BY created_at LIMIT 1 \gset
SELECT id AS autre_profil_veto FROM user_profiles
 WHERE uid = :'veto' AND id <> :'clinique' LIMIT 1 \gset

BEGIN;
-- Données fictives (en super-utilisateur)
INSERT INTO animaux (id, nom, espece, uid_proprietaire) VALUES ('test_clinique_animal', 'Testou', 'chien', :'proprio');
INSERT INTO animal_access (animal_id, pro_profile_id, granted_by_profile_id, statut) VALUES ('test_clinique_animal', :'clinique', :'proprio_profil', 'active');
INSERT INTO employes (uid_eleveur, eleveur_profile_id, uid_employe, employe_profile_id, actif, role_pro)
  VALUES (:'veto', :'clinique', :'emp', :'emp_profil', true, 'asv');
INSERT INTO employe_permissions (eleveur_profile_id, employe_profile_id, permission) VALUES
  (:'clinique', :'emp_profil', 'vet_patients'),
  (:'clinique', :'emp_profil', 'vet_cr_rediger');
INSERT INTO comptes_rendus (id, pro_uid, pro_profile_id, animal_id, owner_uid, contenu, statut)
  VALUES ('00000000-0000-0000-0000-0000000000a1', :'veto', :'clinique', 'test_clinique_animal', :'proprio', 'CR validé', 'valide'),
         ('00000000-0000-0000-0000-0000000000a2', :'veto', :'clinique', 'test_clinique_animal', :'proprio', 'CR brouillon', 'brouillon');
-- CR d'un AUTRE profil du même vétérinaire (multi-profil) — s'il en a un.
INSERT INTO comptes_rendus (id, pro_uid, pro_profile_id, animal_id, owner_uid, contenu, statut)
  SELECT '00000000-0000-0000-0000-0000000000a3', :'veto', :'autre_profil_veto'::uuid, 'test_clinique_animal', :'proprio', 'CR autre profil', 'valide'
  WHERE :'autre_profil_veto' <> '';
INSERT INTO ordonnances (id, pro_uid, pro_profile_id, animal_id, owner_uid, doc_url, notes)
  VALUES ('00000000-0000-0000-0000-0000000000b1', :'veto', :'clinique', 'test_clinique_animal', :'proprio', 'https://x/ordo.pdf', 'ordo');

\echo '── ASV (patients + rédiger, sans valider ni ordonnances)'
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'emp')::text, true) \gset x_
SELECT '   voit l''animal patient (1)              → ' || count(*) FROM animaux WHERE id = 'test_clinique_animal';
SELECT '   voit l''accès patient (1)               → ' || count(*) FROM animal_access WHERE animal_id = 'test_clinique_animal';
SELECT '   voit les CR de la clinique (2)         → ' || count(*) FROM comptes_rendus WHERE animal_id = 'test_clinique_animal' AND pro_profile_id = :'clinique';
SELECT '   voit le CR d''un autre profil (0)       → ' || count(*) FROM comptes_rendus WHERE id = '00000000-0000-0000-0000-0000000000a3';
SELECT '   voit l''ordonnance (1)                  → ' || count(*) FROM ordonnances WHERE animal_id = 'test_clinique_animal';
WITH i AS (INSERT INTO comptes_rendus (pro_uid, pro_profile_id, animal_id, owner_uid, contenu, statut)
  VALUES (:'veto', :'clinique', 'test_clinique_animal', :'proprio', 'tente validé', 'valide') RETURNING statut, redige_par_uid = :'emp' AS moi)
SELECT '   rédige, forcé en brouillon (brouillon t) → ' || statut || ' ' || moi FROM i;
SAVEPOINT s1;
UPDATE comptes_rendus SET contenu = 'modif' WHERE id = '00000000-0000-0000-0000-0000000000a1';
\echo '   ↑ modifier un CR validé : ERREUR attendue (déjà validé)'
ROLLBACK TO SAVEPOINT s1;
WITH u AS (UPDATE comptes_rendus SET statut = 'valide' WHERE id = '00000000-0000-0000-0000-0000000000a2' RETURNING statut)
SELECT '   valide un brouillon (reste brouillon)  → ' || coalesce(string_agg(statut, ','), 'aucune ligne') FROM u;
SAVEPOINT s2;
INSERT INTO ordonnances (pro_uid, pro_profile_id, animal_id, owner_uid, doc_url, notes)
  VALUES (:'veto', :'clinique', 'test_clinique_animal', :'proprio', 'https://x/o.pdf', 'x');
\echo '   ↑ créer une ordonnance : ERREUR RLS attendue'
ROLLBACK TO SAVEPOINT s2;
RESET ROLE;

\echo '── Praticien (droit valider + ordonnances ajoutés)'
INSERT INTO employe_permissions (eleveur_profile_id, employe_profile_id, permission) VALUES
  (:'clinique', :'emp_profil', 'vet_cr_valider'), (:'clinique', :'emp_profil', 'vet_ordonnances');
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'emp')::text, true) \gset x_
WITH u AS (UPDATE comptes_rendus SET statut = 'valide' WHERE id = '00000000-0000-0000-0000-0000000000a2'
  RETURNING statut, valide_par_uid = :'emp' AS moi, valide_le IS NOT NULL AS date)
SELECT '   valide le brouillon (valide t t)       → ' || statut || ' ' || moi || ' ' || date FROM u;
WITH i AS (INSERT INTO ordonnances (pro_uid, pro_profile_id, animal_id, owner_uid, doc_url, notes)
  VALUES (:'veto', :'clinique', 'test_clinique_animal', :'proprio', 'https://x/o.pdf', 'x') RETURNING 1)
SELECT '   crée une ordonnance (1)                → ' || count(*) FROM i;
RESET ROLE;

\echo '── Employé désactivé'
UPDATE employes SET actif = false WHERE eleveur_profile_id = :'clinique' AND uid_employe = :'emp';
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'emp')::text, true) \gset x_
SELECT '   voit les CR (0)                        → ' || count(*) FROM comptes_rendus WHERE animal_id = 'test_clinique_animal';
SELECT '   voit l''accès patient (0)               → ' || count(*) FROM animal_access WHERE animal_id = 'test_clinique_animal';
RESET ROLE;
UPDATE employes SET actif = true WHERE eleveur_profile_id = :'clinique' AND uid_employe = :'emp';

\echo '── Propriétaire de l''animal'
INSERT INTO comptes_rendus (id, pro_uid, pro_profile_id, animal_id, owner_uid, contenu, statut)
  VALUES ('00000000-0000-0000-0000-0000000000a4', :'veto', :'clinique', 'test_clinique_animal', :'proprio', 'brouillon 2', 'brouillon');
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'proprio')::text, true) \gset x_
SELECT '   voit le brouillon (0)                  → ' || count(*) FROM comptes_rendus WHERE id = '00000000-0000-0000-0000-0000000000a4';
SELECT '   voit le CR validé (1)                  → ' || count(*) FROM comptes_rendus WHERE id = '00000000-0000-0000-0000-0000000000a1';
RESET ROLE;

\echo '── Vétérinaire gérant'
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'veto')::text, true) \gset x_
SELECT '   voit le brouillon (1)                  → ' || count(*) FROM comptes_rendus WHERE id = '00000000-0000-0000-0000-0000000000a4';
WITH u AS (UPDATE comptes_rendus SET statut = 'valide' WHERE id = '00000000-0000-0000-0000-0000000000a4' RETURNING statut)
SELECT '   valide le brouillon (valide)           → ' || statut FROM u;
RESET ROLE;

\echo '── Inconnu (autre compte, non employé)'
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', json_build_object('sub', 'inconnu_test_xyz')::text, true) \gset x_
SELECT '   voit les CR (0)                        → ' || count(*) FROM comptes_rendus WHERE animal_id = 'test_clinique_animal';
SELECT '   voit l''accès patient (0)               → ' || count(*) FROM animal_access WHERE animal_id = 'test_clinique_animal';
RESET ROLE;

ROLLBACK;
