-- Tâche « rappel du carnet » (functions/sante.js : « Antiparasitaire — 5 animaux »)
-- (12/11/2026) : soin, produit et animaux concernés gardés sur la tâche, pour
-- ouvrir le formulaire de soin prérempli et vérifier le carnet avant de cocher
-- (site : lib/soin-depuis-tache.ts ; appli : lib/utils/soin_depuis_tache.dart).
-- { "table": "antiparasitaires", "produit": "Virbac", "animal_ids": ["…"] }
-- Les tâches déjà créées sont lues depuis leurs notes (« Animaux : … »).
-- Idempotent.
ALTER TABLE public.taches_elevage ADD COLUMN IF NOT EXISTS soin_rappel JSONB;
