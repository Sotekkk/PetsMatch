-- Correctif ponctuel : re-titre les agenda_events de type RDV avec le nom du
-- BON profil (client_profile_id / pro_profile_id), pas le profil is_main.
-- Cause : anciens agenda_events créés avant le fix _rdvEventNames — un compte
-- multi-profils voyait « RDV avec Pomsky de la Luna » au lieu du particulier.
-- Note : rdv.pro_profile_id / rdv.client_profile_id sont des colonnes TEXT,
-- user_profiles.id est un UUID -> on compare en ::text partout.

-- Nom lisible d'un profil : particulier -> prénom nom ; pro/asso -> nom.
CREATE OR REPLACE FUNCTION _nom_profil(p_id TEXT) RETURNS TEXT AS $$
  SELECT COALESCE(
    NULLIF(TRIM(COALESCE(firstname,'') || ' ' || COALESCE(lastname,'')), ''),
    NULLIF(TRIM(COALESCE(nom,'')), '')
  )
  FROM user_profiles WHERE id::text = p_id;
$$ LANGUAGE sql STABLE;

-- 1. Événements « côté client » (rdv_id renseigné) : titre = « RDV avec <pro> »
UPDATE agenda_events ae
SET titre = 'RDV avec ' || _nom_profil(r.pro_profile_id::text),
    updated_at = now()
FROM rdv r
WHERE ae.type = 'rdv'
  AND ae.rdv_id::text = r.id::text
  AND r.pro_profile_id IS NOT NULL
  AND _nom_profil(r.pro_profile_id::text) IS NOT NULL
  AND ae.titre IS DISTINCT FROM 'RDV avec ' || _nom_profil(r.pro_profile_id::text)
  AND ae.titre LIKE 'RDV avec %';

-- 2. Événements « côté pro » (couleur = 'rdv:<id>') : titre = « RDV avec <client> »
UPDATE agenda_events ae
SET titre = 'RDV avec ' || _nom_profil(r.client_profile_id::text),
    updated_at = now()
FROM rdv r
WHERE ae.type = 'rdv'
  AND ae.rdv_id IS NULL
  AND ae.couleur LIKE 'rdv:%'
  AND r.id::text = substring(ae.couleur from 5)
  AND r.client_profile_id IS NOT NULL
  AND _nom_profil(r.client_profile_id::text) IS NOT NULL
  AND ae.titre IS DISTINCT FROM 'RDV avec ' || _nom_profil(r.client_profile_id::text)
  AND ae.titre LIKE 'RDV avec %';

DROP FUNCTION _nom_profil(TEXT);
