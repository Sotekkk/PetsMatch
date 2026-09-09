-- Créneaux garde typés : une plage `creneaux_pro` peut être réservée à la
-- garde-journée (hébergement) OU aux prestations courtes (promenade / visite),
-- OU aux deux (NULL = comportement historique). Idempotent.

ALTER TABLE public.creneaux_pro
  ADD COLUMN IF NOT EXISTS type_garde text
    CHECK (type_garde IS NULL OR type_garde IN ('journee', 'prestation'));

CREATE INDEX IF NOT EXISTS idx_creneaux_pro_type_garde
  ON public.creneaux_pro (pro_profile_id, date, type_garde);
