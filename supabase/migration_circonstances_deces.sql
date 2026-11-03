-- Décès : circonstances en texte libre, en plus de la cause (03/11/2026).
-- Saisies à la déclaration du décès (fiche animal, registre des entrées /
-- sorties) et reprises au registre. Idempotent.
BEGIN;
ALTER TABLE public.animaux ADD COLUMN IF NOT EXISTS circonstances_deces TEXT;
ALTER TABLE public.registre_mouvements ADD COLUMN IF NOT EXISTS circonstances_deces TEXT;
COMMIT;
