-- Traçabilité des factures : lien optionnel vers le RDV / l'animal / le client
-- d'origine. Sert d'abord à la garde (facturer une prestation depuis le
-- registre des visites ou l'agenda), réutilisable par taxi / toilettage /
-- photographe ensuite. Colonnes NULLABLES — n'affectent ni les factures
-- existantes ni les triggers de numérotation / d'inaltérabilité.
-- Idempotent.

ALTER TABLE public.factures
  ADD COLUMN IF NOT EXISTS source_rdv_id     uuid REFERENCES public.rdv(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS source_animal_id  text,
  ADD COLUMN IF NOT EXISTS client_uid        text,
  ADD COLUMN IF NOT EXISTS client_profile_id uuid REFERENCES public.user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_factures_source_rdv    ON public.factures (source_rdv_id);
CREATE INDEX IF NOT EXISTS idx_factures_source_animal ON public.factures (source_animal_id);
CREATE INDEX IF NOT EXISTS idx_factures_client        ON public.factures (client_uid, client_profile_id);

-- Marque chaque RDV couvert par une facture (une garde de plusieurs jours = N
-- lignes `rdv`, toutes rattachées à la même facture). `source_rdv_id` ci-dessus
-- garde le RDV « ancre » ; `rdv.facture_id` couvre tous les jours facturés.
ALTER TABLE public.rdv
  ADD COLUMN IF NOT EXISTS facture_id text;
CREATE INDEX IF NOT EXISTS idx_rdv_facture ON public.rdv (facture_id);
