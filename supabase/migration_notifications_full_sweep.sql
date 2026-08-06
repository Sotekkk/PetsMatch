-- Migration : backfill notifications.profile_id — passage complet
-- Suite de migration_notifications_backfill_employee_inventaire.sql.
-- Corrige la fuite cross-profil sur ~25 types de notifications
-- supplémentaires découverts lors d'un audit exhaustif de tous les points
-- d'insertion (Dart + web + Cloud Functions + fonction Netlify de rappels).
-- Déjà exécuté manuellement en production le 2026-08-06 (script ponctuel
-- via l'API REST Supabase) — ce fichier documente le backfill pour
-- traçabilité et permet de le rejouer sur un autre environnement.

-- ── place_favori → profil pro propriétaire du lieu (petfriendly_places.pro_profile_id) ──
UPDATE notifications n
SET profile_id = p.pro_profile_id::text
FROM petfriendly_places p
WHERE p.id::text = (n.data->>'placeId')
  AND n.type = 'place_favori' AND n.profile_id IS NULL AND p.pro_profile_id IS NOT NULL;

-- ── animal_en_accueil → profil particulier de la famille d'accueil ──
UPDATE notifications n
SET profile_id = up.id::text
FROM user_profiles up
WHERE up.uid = n.uid AND up.profile_type = 'particulier'
  AND n.type = 'animal_en_accueil' AND n.profile_id IS NULL;

-- ── balade_ludique_xp, petfriend_request, petfriend_accepted, promenade_* →
-- profil particulier du destinataire (fonctionnalités "grand public") ──
UPDATE notifications n
SET profile_id = up.id::text
FROM user_profiles up
WHERE up.uid = n.uid AND up.profile_type = 'particulier'
  AND n.type IN ('balade_ludique_xp', 'petfriend_request', 'petfriend_accepted',
                 'promenade_join', 'promenade_accepte', 'promenade_refuse',
                 'promenade_annulee', 'promenade_modifiee', 'promenade_message',
                 'alerte_perdu')
  AND n.profile_id IS NULL;

-- ── cession_confirmee, cession_revoquee, cession_animal, cession_signature_demandee
-- → profil is_main de l'acquéreur ──
UPDATE notifications n
SET profile_id = up.id::text
FROM user_profiles up
WHERE up.uid = n.uid AND up.is_main = true
  AND n.type IN ('cession_confirmee', 'cession_revoquee', 'cession_animal',
                 'cession_signature_demandee')
  AND n.profile_id IS NULL;

-- ── cession_signee_acquereur → profil eleveur du cédant ──
UPDATE notifications n
SET profile_id = up.id::text
FROM user_profiles up
WHERE up.uid = n.uid AND up.profile_type = 'eleveur'
  AND n.type = 'cession_signee_acquereur' AND n.profile_id IS NULL;

-- ── sante_vet, education_rapport, write_access_requested → propriétaire de
-- l'animal via animaux_proprietes.profile_id_proprio (data->>'animalId') ──
UPDATE notifications n
SET profile_id = ap.profile_id_proprio::text
FROM animaux_proprietes ap
WHERE ap.animal_id::text = (n.data->>'animalId')
  AND ap.date_fin IS NULL
  AND n.type IN ('sante_vet', 'education_rapport', 'write_access_requested')
  AND n.profile_id IS NULL AND ap.profile_id_proprio IS NOT NULL;

-- ── visite_rapport → rdv.client_profile_id (pas de animalId direct, note le
-- lien via rdv si data en contient un — sinon laissé de côté) ──
-- (aucune ligne historique trouvée au moment du backfill — rien à rejouer)

-- ── devis_recu → devis.client_profile_id (data->>'devis_id') ──
UPDATE notifications n
SET profile_id = d.client_profile_id::text
FROM devis d
WHERE d.id::text = (n.data->>'devis_id')
  AND n.type = 'devis_recu' AND n.profile_id IS NULL AND d.client_profile_id IS NOT NULL;

-- ── devis_accepte / devis_refuse → devis.pro_profile_id (data->>'devis_id') ──
UPDATE notifications n
SET profile_id = d.pro_profile_id::text
FROM devis d
WHERE d.id::text = (n.data->>'devis_id')
  AND n.type IN ('devis_accepte', 'devis_refuse')
  AND n.profile_id IS NULL AND d.pro_profile_id IS NOT NULL;

-- ── cours_collectif_inscription → cours_collectifs.pro_profile_id (data->>'coursId') ──
UPDATE notifications n
SET profile_id = c.pro_profile_id::text
FROM cours_collectifs c
WHERE c.id::text = (n.data->>'coursId')
  AND n.type = 'cours_collectif_inscription'
  AND n.profile_id IS NULL AND c.pro_profile_id IS NOT NULL;

-- ── pension_acces_reponse, vet_access_reponse → animal_access.pro_profile_id
-- (data->>'animalId', restreint aux profils du destinataire uid) ──
UPDATE notifications n
SET profile_id = aa.pro_profile_id::text
FROM animal_access aa
JOIN user_profiles up ON up.id = aa.pro_profile_id
WHERE aa.animal_id::text = (n.data->>'animalId')
  AND up.uid = n.uid
  AND n.type IN ('pension_acces_reponse', 'vet_access_reponse')
  AND n.profile_id IS NULL;

-- ── profil_valide / profil_en_attente / profile_validation → profil du
-- compte correspondant à profile_type (colonne déjà renseignée) ──
UPDATE notifications n
SET profile_id = up.id::text
FROM user_profiles up
WHERE up.uid = n.uid
  AND up.profile_type = n.profile_type
  AND n.type IN ('profil_valide', 'profil_en_attente')
  AND n.profile_id IS NULL AND n.profile_type IS NOT NULL AND n.profile_type <> '';

UPDATE notifications n
SET profile_id = up.id::text
FROM user_profiles up
WHERE up.uid = n.uid
  AND up.profile_type = (n.data->>'profileType')
  AND n.type = 'profile_validation'
  AND n.profile_id IS NULL;

-- ── annonce_expiration → annonces.profile_id (data->>'annonceId') ──
UPDATE notifications n
SET profile_id = a.profile_id::text
FROM annonces a
WHERE a.id::text = (n.data->>'annonceId')
  AND n.type = 'annonce_expiration' AND n.profile_id IS NULL AND a.profile_id IS NOT NULL;

-- ── rdv_confirme / rdv_demande / rdv_modifie → rdv.pro_profile_id ou
-- client_profile_id selon quel côté correspond à notifications.uid
-- (data->>'rdv_id') ──
UPDATE notifications n
SET profile_id = CASE
  WHEN r.pro_uid = n.uid THEN r.pro_profile_id::text
  WHEN r.client_uid = n.uid THEN r.client_profile_id::text
  ELSE NULL
END
FROM rdv r
WHERE r.id::text = (n.data->>'rdv_id')
  AND n.type IN ('rdv_confirme', 'rdv_demande', 'rdv_modifie')
  AND n.profile_id IS NULL;

-- Note : quelques lignes restent volontairement non résolues après ce
-- passage — comptes orphelins sans aucune ligne user_profiles (~8 lignes
-- alerte_perdu/employee_invite d'un même uid supprimé), et 2 lignes
-- rdv_demande dont le data ne contient pas rdv_id. Rien de fiable à y
-- assigner sans risquer une valeur fausse.
