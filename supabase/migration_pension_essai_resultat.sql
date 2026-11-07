-- ══════════════════════════════════════════════════════════════════════════
-- Pension : résultat de l'essai (07/11/2026)
-- ══════════════════════════════════════════════════════════════════════════
-- Page « Demandes de séjour » : après l'essai, la pension le valide.
-- pension_demandes.essai_resultat : 'concluant' | 'non_concluant' (NULL = à valider)
-- pension_demandes.essai_valide_le : date de la validation.
-- Essai non concluant : le séjour réservé est annulé (pension_entrees.statut
-- = 'annule', place libérée), la demande passe « annulee », le client est
-- prévenu (route /api/pension/sejour, action « essai »).
-- Facultatif : rien ne change pour l'existant.
-- ══════════════════════════════════════════════════════════════════════════

BEGIN;
ALTER TABLE public.pension_demandes ADD COLUMN IF NOT EXISTS essai_resultat  TEXT;
ALTER TABLE public.pension_demandes ADD COLUMN IF NOT EXISTS essai_valide_le TIMESTAMPTZ;

-- Séjour annulé (essai non concluant) : gardé pour l'historique, hors registre et planning.
DO $$
DECLARE c text;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
            WHERE conrelid = 'public.pension_entrees'::regclass AND contype = 'c'
              AND pg_get_constraintdef(oid) ILIKE '%statut%'
  LOOP
    EXECUTE format('ALTER TABLE public.pension_entrees DROP CONSTRAINT %I', c);
  END LOOP;
END $$;
ALTER TABLE public.pension_entrees ADD CONSTRAINT pension_entrees_statut_check
  CHECK (statut IN ('en_pension', 'sorti', 'annule'));
COMMIT;
