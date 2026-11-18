-- ============================================================
-- PetsMatch — Toiletteur : forfaits « carte de N séances » (18/11/2026)
-- Même principe que l'éducateur / le pet-sitter :
--   • forfaits_toilettage : catalogue du pro (Mes prestations) — nom,
--     nombre de séances, prix, prestation couverte (vide = toutes) ;
--   • forfait choisi à la réservation (rdv.forfait_id) ou vendu depuis le
--     dossier de la séance → forfaits_souscrits (forfait_toilettage_id),
--     facturé UNE fois (facture_id) ; chaque séance est décomptée
--     (rdv.forfait_souscrit_id) et n'est plus facturée.
-- Idempotent. Exécuter dans Supabase SQL Editor.
-- ============================================================
BEGIN;

CREATE TABLE IF NOT EXISTS public.forfaits_toilettage (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  pro_uid         TEXT NOT NULL,
  pro_profile_id  UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  nom             TEXT NOT NULL,
  prestation_id   UUID REFERENCES public.prestations_toilettage(id) ON DELETE SET NULL,
  nb_seances      INTEGER NOT NULL DEFAULT 5 CHECK (nb_seances > 0),
  prix            NUMERIC NOT NULL DEFAULT 0,
  validite_mois   INTEGER,
  description     TEXT,
  actif           BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_forfaits_toilettage_pro ON public.forfaits_toilettage (pro_profile_id, actif);

ALTER TABLE public.forfaits_toilettage ENABLE ROW LEVEL SECURITY;

-- Catalogue public (affiché sur la fiche du toiletteur et à la réservation).
DROP POLICY IF EXISTS "forfaits_toilettage_select" ON public.forfaits_toilettage;
CREATE POLICY "forfaits_toilettage_select" ON public.forfaits_toilettage FOR SELECT USING (true);

-- Écriture : le pro ou un cogérant actif.
DROP POLICY IF EXISTS "forfaits_toilettage_write" ON public.forfaits_toilettage;
CREATE POLICY "forfaits_toilettage_write" ON public.forfaits_toilettage
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM public.elevage_cogerants c
      WHERE c.uid_gerant = forfaits_toilettage.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM public.elevage_cogerants c
      WHERE c.uid_gerant = forfaits_toilettage.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

GRANT SELECT ON public.forfaits_toilettage TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.forfaits_toilettage TO anon, authenticated;

-- Forfait acheté par un client (souscription) : lien vers le catalogue toilettage
-- et date de fin de validité éventuelle.
ALTER TABLE public.forfaits_souscrits
  ADD COLUMN IF NOT EXISTS forfait_toilettage_id UUID REFERENCES public.forfaits_toilettage(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS prestation_toilettage_id UUID,
  ADD COLUMN IF NOT EXISTS valide_jusqu_au DATE;
CREATE INDEX IF NOT EXISTS idx_forfaits_souscrits_toilettage
  ON public.forfaits_souscrits (pro_profile_id, client_profile_id) WHERE forfait_toilettage_id IS NOT NULL;

-- Déjà créées pour l'éducateur / le pet-sitter (sans effet si présentes).
ALTER TABLE public.forfaits_souscrits ADD COLUMN IF NOT EXISTS facture_id UUID;
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS forfait_souscrit_id UUID;
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS forfait_id UUID;
-- Séance retirée de la carte par le pro (facturée à part) : plus rattachée automatiquement.
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS forfait_exclu BOOLEAN NOT NULL DEFAULT false;

NOTIFY pgrst, 'reload schema';
COMMIT;

-- ROLLBACK
-- ALTER TABLE public.rdv DROP COLUMN IF EXISTS forfait_exclu;
-- ALTER TABLE public.forfaits_souscrits DROP COLUMN IF EXISTS valide_jusqu_au,
--   DROP COLUMN IF EXISTS prestation_toilettage_id, DROP COLUMN IF EXISTS forfait_toilettage_id;
-- DROP TABLE IF EXISTS public.forfaits_toilettage;
