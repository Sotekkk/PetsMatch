-- Personnes autorisées à déposer / récupérer l'animal (pension, pet-sitter),
-- distinctes du propriétaire légal et des contacts d'urgence.
-- Saisies par le propriétaire dans la fiche de l'animal ; affichées dans
-- l'en-tête des fiches professionnelles (ProAnimalEntete) pour la pension et
-- le pet-sitter. Format : [{ "nom": "", "tel": "", "lien": "" }]. Idempotent.
ALTER TABLE public.animaux
  ADD COLUMN IF NOT EXISTS personnes_autorisees JSONB NOT NULL DEFAULT '[]'::jsonb;

NOTIFY pgrst, 'reload schema';
