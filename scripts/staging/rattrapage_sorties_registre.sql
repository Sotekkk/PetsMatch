-- Rattrapage du registre des entrées / sorties : animaux sortis (adopté,
-- transféré, décédé, cédé « sorti ») SANS mouvement de sortie dans
-- registre_mouvements — statut changé par d'anciens chemins qui ne
-- touchaient que animaux.statut (menu de statut du site, fiche chenil,
-- pastille de statut, corrigés depuis).
--
-- Pour chaque animal concerné :
--   • sortie inscrite au registre du profil détenteur (association si
--     is_association, sinon élevage ; repli sur le profil principal),
--     datée de date_sortie si renseignée, sinon de la dernière
--     modification de la fiche (seule date disponible) ;
--   • motif « autre » + cause de mort pour un décès, « cession » sinon ;
--     destinataire repris de la fiche s'il y est ;
--   • date_sortie renseignée si vide ;
--   • propriété du détenteur clôturée (animaux_proprietes.date_fin).
-- Idempotent : ne touche que les animaux encore sans sortie au registre.
BEGIN;

CREATE TEMP TABLE a_rattraper ON COMMIT DROP AS
SELECT a.id::text AS animal_id,
       a.nom,
       a.statut,
       a.uid_eleveur,
       COALESCE(a.date_sortie::date, a.updated_at::date, CURRENT_DATE) AS date_sortie,
       a.cause_mort,
       a.destinataire_nom,
       a.destinataire_qualite,
       a.destinataire_adresse,
       COALESCE(
         (SELECT p.id FROM user_profiles p
           WHERE p.uid = a.uid_eleveur
             AND p.profile_type = CASE WHEN a.is_association THEN 'association' ELSE 'eleveur' END
           LIMIT 1),
         (SELECT p.id FROM user_profiles p WHERE p.uid = a.uid_eleveur AND p.is_main LIMIT 1)
       ) AS profile_id
FROM animaux a
WHERE a.statut IN ('adopte', 'transfere', 'decede', 'sorti')
  AND a.uid_eleveur IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM registre_mouvements m
                  WHERE m.animal_id = a.id::text AND m.type = 'sortie');

-- Aperçu de ce qui va être rattrapé
SELECT nom, statut, date_sortie, (profile_id IS NOT NULL) AS profil_trouve
FROM a_rattraper ORDER BY statut, nom;

INSERT INTO registre_mouvements
  (animal_id, uid_eleveur, eleveur_profile_id, type, date_mouvement, motif,
   cause_mort, destinataire_nom, destinataire_qualite, destinataire_adresse)
SELECT animal_id, uid_eleveur, profile_id, 'sortie', date_sortie,
       CASE WHEN statut = 'decede' THEN 'autre' ELSE 'cession' END,
       CASE WHEN statut = 'decede' THEN NULLIF(cause_mort, '') END,
       NULLIF(destinataire_nom, ''), NULLIF(destinataire_qualite, ''), NULLIF(destinataire_adresse, '')
FROM a_rattraper;

UPDATE animaux a SET date_sortie = r.date_sortie
FROM a_rattraper r
WHERE a.id::text = r.animal_id AND a.date_sortie IS NULL;

UPDATE animaux_proprietes ap SET date_fin = r.date_sortie
FROM a_rattraper r
WHERE ap.animal_id = r.animal_id AND ap.uid_proprio = r.uid_eleveur AND ap.date_fin IS NULL;

-- Contrôle : doit renvoyer 0
SELECT count(*) AS sorties_manquantes_restantes
FROM animaux a
WHERE a.statut IN ('adopte', 'transfere', 'decede', 'sorti') AND a.uid_eleveur IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM registre_mouvements m
                  WHERE m.animal_id = a.id::text AND m.type = 'sortie');

COMMIT;
