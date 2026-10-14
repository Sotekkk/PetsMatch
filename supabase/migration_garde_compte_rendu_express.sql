-- ════════════════════════════════════════════════════════════════════════
-- Pet-sitting — compte rendu express d'une promenade / visite.
-- Les nouvelles envoyées au propriétaire restent dans pension_updates (même
-- table que le journal de garde / pension). On ajoute seulement :
--   • rdv_id   : la prestation concernée (historique de la prestation,
--                « compte rendu envoyé » dans le planning et le registre) ;
--   • incident : signalement clairement identifiable par le propriétaire.
-- Heures réelles : AUCUNE nouvelle colonne — rdv.arrivee_validee_le (début
-- effectif) et rdv.depart_valide_le (fin effective) existent déjà
-- (migration_garde_presence.sql) ; rdv.date_heure (heure prévue) n'est
-- jamais modifiée. Idempotent.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE public.pension_updates
  ADD COLUMN IF NOT EXISTS rdv_id   UUID REFERENCES public.rdv(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS incident BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_pension_updates_rdv ON public.pension_updates (rdv_id) WHERE rdv_id IS NOT NULL;

COMMIT;

NOTIFY pgrst, 'reload schema';
