-- Rattrapage : cessions CONFIRMÉES dont la propriété n'a jamais été
-- transférée (ligne acquéreur absente de animaux_proprietes — bloquée en
-- silence par l'index idx_ap_one_principal). Ex. « test cession »
-- (1791276534757). Deux instructions, à lancer dans l'ordre (le tout d'un
-- coup dans l'éditeur SQL Supabase convient).

-- 1) Clôturer les propriétaires actuels (cédant + co-propriétaires).
WITH a_rattraper AS (
  SELECT a.id AS animal_id, a.uid_acquereur AS uid_acq,
         MAX(COALESCE(c.date_cession, c.confirmed_at::date, CURRENT_DATE)) AS date_cession
    FROM cessions c
    JOIN animaux a ON a.id = c.animal_id::text
   WHERE c.statut = 'confirme' AND a.uid_acquereur IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM animaux_proprietes ap
        WHERE ap.animal_id = a.id AND ap.uid_proprio = a.uid_acquereur
          AND ap.date_fin IS NULL AND ap.statut = 'actif')
   GROUP BY a.id, a.uid_acquereur
)
UPDATE animaux_proprietes ap
   SET date_fin = r.date_cession
  FROM a_rattraper r
 WHERE ap.animal_id = r.animal_id AND ap.date_fin IS NULL
   AND ap.statut = 'actif' AND ap.uid_proprio <> r.uid_acq;

-- 2) Ouvrir l'acquéreur en propriétaire principal (profil particulier par défaut).
WITH a_rattraper AS (
  SELECT a.id AS animal_id, a.uid_acquereur AS uid_acq,
         COALESCE(a.profile_id_acquereur, (
           SELECT up.id FROM user_profiles up
            WHERE up.uid = a.uid_acquereur AND up.profile_type = 'particulier'
            ORDER BY up.is_main DESC NULLS LAST LIMIT 1)) AS profile_acq,
         MAX(COALESCE(c.date_cession, c.confirmed_at::date, CURRENT_DATE)) AS date_cession
    FROM cessions c
    JOIN animaux a ON a.id = c.animal_id::text
   WHERE c.statut = 'confirme' AND a.uid_acquereur IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM animaux_proprietes ap
        WHERE ap.animal_id = a.id AND ap.uid_proprio = a.uid_acquereur
          AND ap.date_fin IS NULL AND ap.statut = 'actif')
   GROUP BY a.id, a.uid_acquereur, a.profile_id_acquereur
)
INSERT INTO animaux_proprietes
  (animal_id, uid_proprio, profile_id_proprio, date_debut, date_fin, role_proprio, statut)
SELECT animal_id, uid_acq, profile_acq, date_cession, NULL, 'principal', 'actif'
  FROM a_rattraper
ON CONFLICT (animal_id, uid_proprio) DO UPDATE
  SET date_fin = NULL, role_proprio = 'principal', statut = 'actif',
      date_debut = EXCLUDED.date_debut,
      profile_id_proprio = COALESCE(EXCLUDED.profile_id_proprio, animaux_proprietes.profile_id_proprio)
RETURNING animal_id, uid_proprio, profile_id_proprio;
