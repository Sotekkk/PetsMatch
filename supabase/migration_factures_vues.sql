-- Bulle rouge « nouvelle facture » côté client (Administratif → Mes Factures).
-- Une ligne par profil client (clé = profile_id, sinon uid) : date de la
-- dernière ouverture de « Mes Factures ». Les factures reçues après cette
-- date sont « non vues ». Partagée appli / site (pas de stockage local).

BEGIN;

CREATE TABLE IF NOT EXISTS public.factures_vues (
  cle    text PRIMARY KEY,
  uid    text NOT NULL,
  vu_le  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.factures_vues ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE ON public.factures_vues TO authenticated;

DROP POLICY IF EXISTS factures_vues_moi ON public.factures_vues;
CREATE POLICY factures_vues_moi ON public.factures_vues
  FOR ALL USING (uid = (auth.jwt() ->> 'sub'))
  WITH CHECK (uid = (auth.jwt() ->> 'sub'));

NOTIFY pgrst, 'reload schema';

COMMIT;
