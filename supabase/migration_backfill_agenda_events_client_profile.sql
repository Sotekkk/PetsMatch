-- ============================================================
-- Backfill : les entrées agenda_events créées côté CLIENT lors de la
-- confirmation d'un RDV (avant ce correctif) n'avaient jamais
-- pro_profile_id renseigné — elles apparaissaient donc sur TOUS les
-- profils du client via la règle de compatibilité "legacy sans profil"
-- (ex : RDV pension visible depuis le profil éleveur).
-- Ce script rattache rétroactivement chaque entrée liée à un RDV
-- (rdv_id non nul) au bon profil client, à partir de rdv.client_profile_id.
-- Exécuter dans Supabase SQL Editor (idempotent, ne touche que les
-- lignes encore mal taguées).
-- ============================================================

UPDATE agenda_events ae
SET pro_profile_id = r.client_profile_id
FROM rdv r
WHERE ae.rdv_id = r.id
  AND ae.uid = r.client_uid
  AND ae.pro_profile_id IS NULL
  AND r.client_profile_id IS NOT NULL;
