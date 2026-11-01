-- Factures : règlements partiels (lot 3 de la refonte de la facturation).
-- 01/11/2026. Idempotent.
--
-- facture_reglements : un paiement (montant, date, mode, référence) sur une
-- facture émise. Le total réglé (factures.montant_regle) et le statut
-- (emise → partiellement_payee → payee) sont recalculés par déclencheur ; le
-- contenu de la facture n'est jamais modifié (garde-fou inchangé). Le PDF
-- affiche « Déjà réglé » et « Reste à payer ».

-- Prérequis (migration_factures_date_paiement.sql), au cas où.
ALTER TABLE public.factures ADD COLUMN IF NOT EXISTS date_paiement timestamptz;
ALTER TABLE public.factures ADD COLUMN IF NOT EXISTS montant_regle numeric(12,2) NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS public.facture_reglements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  facture_id text NOT NULL REFERENCES public.factures(id) ON DELETE CASCADE,
  uid_eleveur text NOT NULL,
  montant numeric(12,2) NOT NULL CHECK (montant > 0),
  date_reglement date NOT NULL DEFAULT current_date,
  mode text,
  reference text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.facture_reglements ALTER COLUMN created_at SET DEFAULT clock_timestamp();
CREATE INDEX IF NOT EXISTS facture_reglements_facture_idx ON public.facture_reglements (facture_id);

ALTER TABLE public.facture_reglements ENABLE ROW LEVEL SECURITY;

-- Lecture : qui peut lire la facture (pro, cogérant, employé « facturation », client).
DROP POLICY IF EXISTS facture_reglements_select ON public.facture_reglements;
CREATE POLICY facture_reglements_select ON public.facture_reglements FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.factures f WHERE f.id = facture_id AND (
    pm_acces_compte(f.uid_eleveur, (f.profile_id)::text, ARRAY['facturation'::text])
    OR (auth.jwt() ->> 'sub') = f.client_uid
    OR is_admin_uid(auth.jwt() ->> 'sub'))));

-- Écriture : le pro (ou son cogérant actif), sur ses propres factures.
DROP POLICY IF EXISTS facture_reglements_write ON public.facture_reglements;
CREATE POLICY facture_reglements_write ON public.facture_reglements FOR ALL
  USING (EXISTS (SELECT 1 FROM public.factures f WHERE f.id = facture_id AND (
    (auth.jwt() ->> 'sub') = f.uid_eleveur
    OR EXISTS (SELECT 1 FROM public.elevage_cogerants c WHERE c.uid_gerant = f.uid_eleveur
      AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL))))
  WITH CHECK (EXISTS (SELECT 1 FROM public.factures f WHERE f.id = facture_id AND f.uid_eleveur = uid_eleveur AND (
    (auth.jwt() ->> 'sub') = f.uid_eleveur
    OR EXISTS (SELECT 1 FROM public.elevage_cogerants c WHERE c.uid_gerant = f.uid_eleveur
      AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL))));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.facture_reglements TO anon, authenticated;

-- Total réglé et statut recalculés à chaque règlement ajouté / supprimé.
CREATE OR REPLACE FUNCTION public.pm_facture_reglements_maj()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  fid text := COALESCE(NEW.facture_id, OLD.facture_id);
  total numeric(12,2);
  dernier record;
BEGIN
  SELECT COALESCE(sum(montant), 0) INTO total FROM facture_reglements WHERE facture_id = fid;
  SELECT date_reglement, mode INTO dernier FROM facture_reglements WHERE facture_id = fid
    ORDER BY date_reglement DESC, created_at DESC LIMIT 1;
  UPDATE factures f SET
    montant_regle = total,
    statut = CASE
      WHEN f.statut IN ('annulee', 'brouillon') THEN f.statut
      WHEN total >= f.total_ttc - 0.005 AND f.total_ttc > 0 THEN 'payee'
      WHEN total > 0 THEN 'partiellement_payee'
      WHEN f.statut IN ('payee', 'partiellement_payee') THEN 'emise'
      ELSE f.statut END,
    date_paiement = CASE WHEN total >= f.total_ttc - 0.005 AND f.total_ttc > 0 THEN dernier.date_reglement::timestamptz ELSE f.date_paiement END,
    mode_paiement = CASE WHEN total >= f.total_ttc - 0.005 AND f.total_ttc > 0 AND dernier.mode IS NOT NULL THEN dernier.mode ELSE f.mode_paiement END
  WHERE f.id = fid;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_facture_reglements_maj ON public.facture_reglements;
CREATE TRIGGER trg_facture_reglements_maj AFTER INSERT OR UPDATE OR DELETE ON public.facture_reglements
  FOR EACH ROW EXECUTE FUNCTION public.pm_facture_reglements_maj();

COMMENT ON COLUMN public.factures.montant_regle IS 'Somme des règlements (facture_reglements) ; statut partiellement_payee / payee recalculé';

NOTIFY pgrst, 'reload schema';
