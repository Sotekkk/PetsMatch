-- Backfill : les contrats "devis éducateur" (type='contrat_education') créés
-- avant la correction du 2026-09-19 n'avaient jamais de client_profile_id
-- dans leur metadata (bug de code, pas de bug de la table documents_animaux
-- elle-même). Résultat : la page "Mes Contrats" ne pouvait pas savoir à quel
-- profil ces documents étaient destinés et les affichait dans TOUS les
-- profils du compte (ex. visibles depuis le profil éleveur alors qu'ils
-- concernent le profil éducateur/pet-sitter).
--
-- Ce script rattache rétroactivement chaque document à son profil correct
-- en le retrouvant via la source d'origine (devis / rdv). Les documents pour
-- lesquels aucune correspondance fiable n'est trouvée restent inchangés (ils
-- continueront d'apparaître partout tant qu'ils ne sont pas corrigés
-- manuellement).

-- 1) Contrats éducation générés depuis un devis : on récupère le
--    client_profile_id déjà stocké sur la ligne `devis` d'origine.
update documents_animaux d
set metadata = jsonb_set(
  coalesce(d.metadata, '{}'::jsonb),
  '{client_profile_id}',
  to_jsonb(dev.client_profile_id::text)
)
from devis dev
where d.type = 'contrat_education'
  and d.metadata ->> 'devis_id' = dev.id::text
  and dev.client_profile_id is not null
  and (d.metadata ->> 'client_profile_id') is null;

-- 2) Contrats de garde/pet-sitting sans client_profile_id : on retrouve le
--    profil via le rendez-vous (rdv) le plus récent portant le même
--    client_uid pour ce même pro_profile_id — c'est la même résolution que
--    celle déjà utilisée à la création dans registre_visites_page.dart.
with cible as (
  select distinct on (d.id)
    d.id as doc_id,
    r.client_profile_id
  from documents_animaux d
  join rdv r
    on r.client_uid = (d.metadata ->> 'client_uid')
   and r.pro_profile_id = d.pro_profile_id
  where d.type = 'contrat_garde'
    and (d.metadata ->> 'client_profile_id') is null
    and r.client_profile_id is not null
  order by d.id, r.date_heure desc
)
update documents_animaux d
set metadata = jsonb_set(
  coalesce(d.metadata, '{}'::jsonb),
  '{client_profile_id}',
  to_jsonb(cible.client_profile_id::text)
)
from cible
where d.id = cible.doc_id;

-- Vérification (à lancer après coup) : documents encore non rattachés.
-- select id, type, metadata ->> 'client_uid', pro_profile_id
-- from documents_animaux
-- where type in ('contrat_education', 'contrat_garde')
--   and (metadata ->> 'client_profile_id') is null;
