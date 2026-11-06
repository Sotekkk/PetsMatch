-- Toiletteur, RDV à plusieurs animaux : une fiche technique / compte rendu
-- (seances_toilettage) PAR ANIMAL du rendez-vous (06/11/2026).
-- Avant : rdv_id UNIQUE → une seule fiche par RDV, le 2e animal ne pouvait pas
-- avoir la sienne. Désormais unique sur (rdv_id, animal_id). Un RDV à un seul
-- animal ne change pas (une fiche). Les fiches existantes restent telles quelles.
-- Code : SeanceToilettageModal / toilettage_seance_page.dart lisent la fiche par
-- rdv_id + animal_id ; fin de séance : un PDF par animal. Idempotent.

BEGIN;

ALTER TABLE public.seances_toilettage DROP CONSTRAINT IF EXISTS seances_toilettage_rdv_id_key;
DROP INDEX IF EXISTS public.seances_toilettage_rdv_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS seances_toilettage_rdv_animal_key
  ON public.seances_toilettage (rdv_id, animal_id);

COMMIT;
