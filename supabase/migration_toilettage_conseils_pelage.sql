-- Toiletteur — compte rendu de séance : conseils de soin du pelage pour le
-- propriétaire (brossage, produits, fréquence, prochain toilettage conseillé),
-- affichés avec le compte rendu partagé (onglet Consultations de l'animal).
-- Idempotent.
ALTER TABLE public.seances_toilettage ADD COLUMN IF NOT EXISTS conseils_pelage TEXT;

NOTIFY pgrst, 'reload schema';
