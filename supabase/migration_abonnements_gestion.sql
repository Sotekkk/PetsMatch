-- Gestion des abonnements par le pro (13/11/2026) : page « Mon abonnement »
-- (site + appli), pause du mensuel (3 mois max), résiliation en fin de
-- période, rappels avant renouvellement annuel, prélèvement refusé (7 jours
-- de grâce puis gratuit), carte bientôt expirée.
--   • resiliation_prevue : résilié, accès jusqu'à date_fin (cancel_at_period_end).
--   • pause_jusquau      : mensuel en pause (pause_collection Stripe), plan gratuit.
--   • grace_jusquau      : prélèvement refusé, fonctionnalités conservées jusque-là.
--   • statuts ajoutés    : 'pause', 'suspendu' (grâce dépassée, paiement à régulariser).
-- Idempotent.
BEGIN;
ALTER TABLE public.abonnements
  ADD COLUMN IF NOT EXISTS resiliation_prevue BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS pause_jusquau TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS grace_jusquau TIMESTAMPTZ;

-- Statuts : contrainte éventuelle élargie (NOT VALID : lignes existantes intactes).
DO $$
DECLARE c text;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
           WHERE conrelid = 'public.abonnements'::regclass AND contype = 'c'
             AND pg_get_constraintdef(oid) ILIKE '%statut%'
  LOOP
    EXECUTE format('ALTER TABLE public.abonnements DROP CONSTRAINT %I', c);
  END LOOP;
END $$;
ALTER TABLE public.abonnements ADD CONSTRAINT abonnements_statut_check
  CHECK (statut IN ('actif', 'grace', 'pause', 'suspendu', 'annule', 'expire', 'essai')) NOT VALID;

NOTIFY pgrst, 'reload schema';
COMMIT;

-- ROLLBACK
-- ALTER TABLE public.abonnements DROP CONSTRAINT IF EXISTS abonnements_statut_check;
-- ALTER TABLE public.abonnements DROP COLUMN IF EXISTS resiliation_prevue, DROP COLUMN IF EXISTS pause_jusquau, DROP COLUMN IF EXISTS grace_jusquau;
