-- ============================================================
-- Backfill : les entrées agenda_events créées côté PRO lors de la
-- confirmation d'un RDV (avant le correctif 36ab6116) n'avaient jamais
-- pro_profile_id renseigné — le RDV confirmé restait invisible dans
-- "Mon Agenda" pour un pro multi-profils (ex : profil éducateur).
-- Ces entrées n'ont pas de rdv_id (seulement un tag couleur:'rdv:<id>'),
-- donc le backfill précédent (migration_backfill_agenda_events_client_profile.sql,
-- côté client) ne les couvrait pas.
-- Exécuter dans Supabase SQL Editor (idempotent, ne touche que les
-- lignes encore mal taguées).
-- ============================================================

UPDATE agenda_events ae
SET pro_profile_id = r.pro_profile_id
FROM rdv r
WHERE ae.uid = r.pro_uid
  AND ae.couleur = 'rdv:' || r.id::text
  AND ae.pro_profile_id IS NULL
  AND r.pro_profile_id IS NOT NULL;
