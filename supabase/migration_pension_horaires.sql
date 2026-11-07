-- ══════════════════════════════════════════════════════════════════════════
-- Pension : horaires d'arrivée / de départ, heure choisie par le client,
-- planning des arrivées et départs (07/11/2026)
-- ══════════════════════════════════════════════════════════════════════════
-- user_profiles.pension_horaires (réglé par la pension, page Tarifs) :
--   { "arrivees": [{"debut":"08:00","fin":"10:00"}, …],
--     "departs":  [{"debut":"17:00","fin":"19:00"}, …],
--     "duree_arrivee_nouveau": 30,   -- minutes, premier séjour
--     "duree_arrivee_habitue": 15,   -- minutes, client déjà venu
--     "duree_depart": 15,            -- minutes
--     "minutes_par_animal": 5,       -- en plus par animal supplémentaire
--     "max_par_creneau": 3 }         -- clients au plus par créneau de 15 min
--   (arrivées et départs partagent ce maximum). NULL = pas d'horaires :
--   le client ne choisit pas d'heure.
-- pension_demandes.heure_arrivee / heure_depart : 'HH:MM' choisis par le client.
-- pension_entrees.heure_*_prevue / duree_*_min : planning (modifiable par la
-- pension à l'acceptation).
-- Toutes les colonnes sont facultatives : rien ne change pour l'existant.
-- ══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.user_profiles     ADD COLUMN IF NOT EXISTS pension_horaires JSONB;

ALTER TABLE public.pension_demandes  ADD COLUMN IF NOT EXISTS heure_arrivee TEXT;
ALTER TABLE public.pension_demandes  ADD COLUMN IF NOT EXISTS heure_depart  TEXT;

ALTER TABLE public.pension_entrees   ADD COLUMN IF NOT EXISTS heure_arrivee_prevue TEXT;
ALTER TABLE public.pension_entrees   ADD COLUMN IF NOT EXISTS heure_depart_prevue  TEXT;
ALTER TABLE public.pension_entrees   ADD COLUMN IF NOT EXISTS duree_arrivee_min    INTEGER;
ALTER TABLE public.pension_entrees   ADD COLUMN IF NOT EXISTS duree_depart_min     INTEGER;

COMMIT;

-- Les vues « *_complet » reprennent les colonnes de user_profiles :
SELECT pm_recreer_vues_perso();
