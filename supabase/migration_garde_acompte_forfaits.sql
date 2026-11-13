-- Pet-sitter : acompte rattaché à la garde, déduit de la facture finale, et
-- forfaits achetés puis décomptés comme ceux du comportementaliste (13/11/2026).
--   • factures.acompte_rdv_id : la garde (1er RDV) dont l'acompte a été demandé.
--     Pas source_rdv_id : les passages restent « à facturer » (solde ensuite).
--   • forfaits_garde.type_prestation : + 'garde_journee' (pack de jours de garde).
--   • forfaits_souscrits.forfait_garde_id / type_prestation_garde : forfait de
--     garde acheté par un client (facturé à l'achat, facture_id), chaque passage
--     décompté par rdv.forfait_souscrit_id (colonne déjà créée pour l'éducateur).
-- Idempotent.
BEGIN;
ALTER TABLE public.factures ADD COLUMN IF NOT EXISTS acompte_rdv_id UUID;
CREATE INDEX IF NOT EXISTS idx_factures_acompte_rdv ON public.factures (acompte_rdv_id) WHERE acompte_rdv_id IS NOT NULL;

ALTER TABLE public.forfaits_garde DROP CONSTRAINT IF EXISTS forfaits_garde_type_chk;
ALTER TABLE public.forfaits_garde
  ADD CONSTRAINT forfaits_garde_type_chk CHECK (type_prestation IN ('visite', 'promenade', 'garde_journee'));

ALTER TABLE public.forfaits_souscrits
  ADD COLUMN IF NOT EXISTS forfait_garde_id UUID REFERENCES public.forfaits_garde(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS type_prestation_garde TEXT;
CREATE INDEX IF NOT EXISTS idx_forfaits_souscrits_garde
  ON public.forfaits_souscrits (pro_profile_id, client_profile_id) WHERE forfait_garde_id IS NOT NULL;

ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS forfait_souscrit_id UUID;
NOTIFY pgrst, 'reload schema';
COMMIT;

-- ROLLBACK
-- ALTER TABLE public.forfaits_souscrits DROP COLUMN IF EXISTS type_prestation_garde, DROP COLUMN IF EXISTS forfait_garde_id;
-- ALTER TABLE public.forfaits_garde DROP CONSTRAINT IF EXISTS forfaits_garde_type_chk;
-- ALTER TABLE public.forfaits_garde ADD CONSTRAINT forfaits_garde_type_chk CHECK (type_prestation IN ('visite', 'promenade'));
-- ALTER TABLE public.factures DROP COLUMN IF EXISTS acompte_rdv_id;
