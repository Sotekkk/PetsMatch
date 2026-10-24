-- ════════════════════════════════════════════════════════════════════════
-- Traitements : quantité par prise + étapes saisies par le propriétaire.
--
--   • rappel_quantites TEXT[] : quantité de chaque prise, alignée sur
--     rappel_heures (même position) — ex. heures {08:00,20:00},
--     quantités {"1 cp","1/2 cp"}. Vide / absente : la posologie générale
--     s'applique. La notification dit « ½ cp de Metacam à 20:00 ».
--   • groupe_id TEXT : étapes successives d'une même posologie progressive
--     (« 1 cp 3×/jour 4 jours, puis ½ cp 3×/jour 3 jours »), ajoutées par le
--     propriétaire avec « Ajouter l'étape suivante ». Les notes gardent le
--     préfixe « Phase i/n » (format du compte rendu vétérinaire).
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════
ALTER TABLE public.traitements
  ADD COLUMN IF NOT EXISTS rappel_quantites TEXT[],
  ADD COLUMN IF NOT EXISTS groupe_id        TEXT;

CREATE INDEX IF NOT EXISTS idx_traitements_groupe ON public.traitements (groupe_id) WHERE groupe_id IS NOT NULL;

NOTIFY pgrst, 'reload schema';
