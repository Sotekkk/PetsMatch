-- Tests « prise de RDV clinique » (migration_clinique_rdv.sql).
-- Transaction ANNULÉE : données fictives, aucune trace.
-- Usage : psql "$STAGING_DB_URL" -f scripts/staging/test_clinique_rdv.sql
\set QUIET on
\pset footer off
\pset tuples_only on
\set ON_ERROR_STOP off

SELECT id AS clinique, uid AS veto FROM user_profiles
 WHERE profile_type NOT IN ('particulier') ORDER BY created_at LIMIT 1 \gset
SELECT id AS prat_profil, uid AS prat FROM user_profiles
 WHERE profile_type = 'particulier' AND uid <> :'veto' ORDER BY created_at LIMIT 1 \gset
SELECT id AS client_profil, uid AS client FROM user_profiles
 WHERE profile_type = 'particulier' AND uid NOT IN (:'veto', :'prat') ORDER BY created_at LIMIT 1 \gset
SELECT id AS client2_profil, uid AS client2 FROM user_profiles
 WHERE profile_type = 'particulier' AND uid NOT IN (:'veto', :'prat', :'client') ORDER BY created_at LIMIT 1 \gset

BEGIN;
-- La clinique est un profil vétérinaire (le temps du test).
UPDATE user_profiles SET profile_type = 'veterinaire', salles_par_motif = '{"chirurgie":"chirurgie"}' WHERE id = :'clinique';
INSERT INTO employes (uid_eleveur, eleveur_profile_id, uid_employe, employe_profile_id, actif, role_pro)
  VALUES (:'veto', :'clinique', :'prat', :'prat_profil', true, 'veterinaire');
INSERT INTO salles_clinique (id, clinique_profile_id, nom, type_salle, ordre) VALUES
  ('00000000-0000-0000-0000-00000000c001', :'clinique', 'Consult 1', 'consultation', 1),
  ('00000000-0000-0000-0000-00000000c002', :'clinique', 'Consult 2', 'consultation', 2),
  ('00000000-0000-0000-0000-00000000c003', :'clinique', 'Bloc', 'chirurgie', 3);

\echo '── Client 1 réserve le titulaire, 10h, consultation'
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'client')::text, true) \gset x_
WITH i AS (INSERT INTO rdv (pro_uid, pro_profile_id, client_uid, client_profile_id, date_heure, duree_minutes, motif, statut)
  VALUES (:'veto', :'clinique', :'client', :'client_profil', '2030-01-07 10:00+00', 30, 'Consultation', 'demande')
  RETURNING salle_id)
SELECT '   salle attribuée (c001 = Consult 1)     → ' || coalesce(right(salle_id::text, 4), 'aucune') FROM i;
RESET ROLE;

\echo '── Client 2 tente le même titulaire, 10h15 (chevauche)'
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'client2')::text, true) \gset x_
SAVEPOINT a;
INSERT INTO rdv (pro_uid, pro_profile_id, client_uid, client_profile_id, date_heure, duree_minutes, motif, statut)
  VALUES (:'veto', :'clinique', :'client2', :'client2_profil', '2030-01-07 10:15+00', 30, 'Consultation', 'demande');
\echo '   ↑ ERREUR attendue : créneau pris'
ROLLBACK TO SAVEPOINT a;
\echo '── Client 2 prend le praticien employé, 10h15'
WITH i AS (INSERT INTO rdv (pro_uid, pro_profile_id, client_uid, client_profile_id, date_heure, duree_minutes, motif, statut, instructeur_profile_id)
  VALUES (:'veto', :'clinique', :'client2', :'client2_profil', '2030-01-07 10:15+00', 30, 'Consultation', 'demande', :'prat_profil')
  RETURNING salle_id)
SELECT '   accepté, salle (c002 = Consult 2)      → ' || coalesce(right(salle_id::text, 4), 'aucune') FROM i;
\echo '── Plages occupées vues par le client 2 (2 RDV, dont 1 d''un autre client)'
SELECT '   plages occupées (2)                    → ' || count(*) FROM pm_plages_occupees(:'clinique', '2030-01-07 00:00+00', '2030-01-08 00:00+00');
SELECT '   lit les rdv bruts de l''autre client (0)→ ' || count(*) FROM rdv WHERE client_uid = :'client';
RESET ROLE;

\echo '── Plus de salle de consultation à 10h20 (2/2 prises), chirurgie OK'
-- 3e praticien fictif : un RDV pro-forcé pour occuper… on teste via un client sur le praticien libre ?
-- Les 2 praticiens sont pris : on libère le test salle avec un RDV sans praticien en conflit.
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'client')::text, true) \gset x_
WITH i AS (INSERT INTO rdv (pro_uid, pro_profile_id, client_uid, client_profile_id, date_heure, duree_minutes, motif, statut)
  VALUES (:'veto', :'clinique', :'client', :'client_profil', '2030-01-07 11:00+00', 60, 'Chirurgie', 'demande')
  RETURNING salle_id)
SELECT '   chirurgie (c003 = Bloc)               → ' || coalesce(right(salle_id::text, 4), 'aucune') FROM i;
RESET ROLE;

\echo '── Salles pleines : RDV saisi par le véto (forcé) accepté'
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'veto')::text, true) \gset x_
WITH i AS (INSERT INTO rdv (pro_uid, pro_profile_id, client_nom_manuel, date_heure, duree_minutes, motif, statut, cree_par_pro)
  VALUES (:'veto', :'clinique', 'Client tél.', '2030-01-07 10:20+00', 20, 'Consultation', 'confirme', true)
  RETURNING salle_id)
SELECT '   RDV forcé, sans salle (aucune)         → ' || coalesce(salle_id::text, 'aucune') FROM i;
RESET ROLE;

\echo '── Indisponibilité du praticien → client refusé'
INSERT INTO agenda_events (uid, pro_profile_id, titre, type, date_debut, date_fin, praticien_profile_id)
  VALUES (:'veto', :'clinique', 'Formation', 'indisponible', '2030-01-07 14:00+00', '2030-01-07 16:00+00', :'prat_profil');
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'client')::text, true) \gset x_
SELECT '   indisponibilité visible (1)            → ' || count(*) FROM pm_plages_occupees(:'clinique', '2030-01-07 14:00+00', '2030-01-07 15:00+00') WHERE indisponible;
SAVEPOINT b;
INSERT INTO rdv (pro_uid, pro_profile_id, client_uid, client_profile_id, date_heure, duree_minutes, motif, statut, instructeur_profile_id)
  VALUES (:'veto', :'clinique', :'client', :'client_profil', '2030-01-07 15:00+00', 30, 'Consultation', 'demande', :'prat_profil');
\echo '   ↑ ERREUR attendue : praticien indisponible'
ROLLBACK TO SAVEPOINT b;
SELECT '   praticiens de la clinique (2)          → ' || count(*) FROM pm_praticiens_clinique(:'clinique');
SELECT '   salles actives (3)                     → ' || count(*) FROM pm_salles_actives(:'clinique');
SELECT '   lit la table des salles (0, client)    → ' || count(*) FROM salles_clinique WHERE clinique_profile_id = :'clinique';
RESET ROLE;

\echo '── Praticien employé : gère SES créneaux, pas ceux du titulaire'
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'prat')::text, true) \gset x_
WITH i AS (INSERT INTO creneaux_pro (pro_uid, pro_profile_id, praticien_profile_id, date, heure_debut, heure_fin, statut)
  VALUES (:'veto', :'clinique', :'prat_profil', '2030-01-08', '09:00', '12:00', 'disponible') RETURNING 1)
SELECT '   crée son créneau (1)                   → ' || count(*) FROM i;
SAVEPOINT c;
INSERT INTO creneaux_pro (pro_uid, pro_profile_id, date, heure_debut, heure_fin, statut)
  VALUES (:'veto', :'clinique', '2030-01-08', '09:00', '12:00', 'disponible');
\echo '   ↑ ERREUR RLS attendue : créneau du titulaire'
ROLLBACK TO SAVEPOINT c;
RESET ROLE;

\echo '── Salle attribuée au praticien (Consult 2) : prioritaire même si Consult 1 est libre'
INSERT INTO creneaux_pro (pro_uid, pro_profile_id, praticien_profile_id, date, heure_debut, heure_fin, statut, salle_id)
  VALUES (:'veto', :'clinique', :'prat_profil', '2030-01-09', '10:00', '11:00', 'disponible', '00000000-0000-0000-0000-00000000c002');
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'client')::text, true) \gset x_
WITH i AS (INSERT INTO rdv (pro_uid, pro_profile_id, client_uid, client_profile_id, date_heure, duree_minutes, motif, statut, instructeur_profile_id)
  VALUES (:'veto', :'clinique', :'client', :'client_profil', '2030-01-09 10:15:00 Europe/Paris', 30, 'Consultation', 'demande', :'prat_profil')
  RETURNING salle_id)
SELECT '   salle du praticien (c002)              → ' || coalesce(right(salle_id::text, 4), 'aucune') FROM i;
RESET ROLE;

\echo '── Autre métier (non vétérinaire) : aucun contrôle ajouté'
UPDATE user_profiles SET profile_type = 'toilettage' WHERE id = :'clinique';
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'client2')::text, true) \gset x_
WITH i AS (INSERT INTO rdv (pro_uid, pro_profile_id, client_uid, client_profile_id, date_heure, duree_minutes, motif, statut)
  VALUES (:'veto', :'clinique', :'client2', :'client2_profil', '2030-01-07 10:00+00', 30, 'Toilettage', 'demande') RETURNING 1)
SELECT '   accepté sans contrôle (1)              → ' || count(*) FROM i;
RESET ROLE;

ROLLBACK;
