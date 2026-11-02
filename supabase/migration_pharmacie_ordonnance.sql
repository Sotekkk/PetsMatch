-- Pharmacie de la clinique → ordonnance (complément du lot 2 des documents
-- vétérinaires). 02/11/2026.
--
-- Informations fixes d'un médicament du stock, reprises sur la ligne
-- d'ordonnance quand le médicament est choisi dans la pharmacie (rien n'est
-- écrasé, tout reste modifiable ; la dose n'est jamais préremplie) :
--   presentation      présentation et concentration (« comprimé sécable 50 mg »)
--   principe_actif
--   contenance        nombre d'unités par conditionnement (30)
--   contenance_unite  unité de prise du conditionnement (« comprimés », « mL »)
--   voie              voie d'administration
--   instructions      instructions habituelles (« pendant le repas »)
--   mentions          mentions réglementaires (temps d'attente, catégorie)
-- La contenance sert à SUGGÉRER la quantité à délivrer (à vérifier).
-- Aucune modification des droits. Idempotent.

BEGIN;

ALTER TABLE public.inventaire_items
  ADD COLUMN IF NOT EXISTS presentation     TEXT,
  ADD COLUMN IF NOT EXISTS principe_actif   TEXT,
  ADD COLUMN IF NOT EXISTS contenance       NUMERIC,
  ADD COLUMN IF NOT EXISTS contenance_unite TEXT,
  ADD COLUMN IF NOT EXISTS voie             TEXT,
  ADD COLUMN IF NOT EXISTS instructions     TEXT,
  ADD COLUMN IF NOT EXISTS mentions         TEXT;

NOTIFY pgrst, 'reload schema';

COMMIT;
