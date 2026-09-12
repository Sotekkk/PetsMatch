-- Traçabilité des factures pension dans le moteur commun `factures` (au lieu
-- de la table dédiée `pension_factures`, désormais réservée à l'historique
-- pré-migration). Sert le registre pension (badge « facturé », alerte
-- débiteurs) pour retrouver la facture d'un séjour donné.
-- Colonne NULLABLE — n'affecte ni les factures existantes ni les triggers de
-- numérotation / d'inaltérabilité. Idempotent.

ALTER TABLE public.factures
  ADD COLUMN IF NOT EXISTS source_pension_entree_id uuid
    REFERENCES public.pension_entrees(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_factures_source_pension_entree
  ON public.factures (source_pension_entree_id);
