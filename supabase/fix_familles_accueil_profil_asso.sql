-- ════════════════════════════════════════════════════════════════════════
-- Familles d'accueil rangées sous le mauvais profil.
--
-- L'appli (familles_accueil_page.dart) prenait le profil is_main du compte
-- comme association_profile_id. Pour un compte élevage + association, c'est
-- le profil ÉLEVAGE → la famille n'apparaissait pas sur le site (filtré par
-- profil actif) et mélangeait les profils. Corrigé dans l'appli (profil
-- association) ; ici, rattachement des lignes existantes au profil
-- association du même compte.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

UPDATE familles_accueil f
SET association_profile_id = ap.id
FROM user_profiles ap, user_profiles cur
WHERE ap.uid = f.association_uid
  AND ap.profile_type = 'association'
  AND cur.id::text = f.association_profile_id::text
  AND cur.profile_type <> 'association';

-- Contrôle : doit renvoyer 0
SELECT count(*) AS restant_mal_rattache
FROM familles_accueil f
JOIN user_profiles p ON p.id::text = f.association_profile_id::text
WHERE p.profile_type <> 'association';

COMMIT;
