-- Réservation en ligne garde : capacité par créneau + réglage chevauchement.
-- Idempotent.

-- Nombre de places d'un créneau (garde à domicile : plusieurs animaux le même
-- jour). Reste à 1 pour tous les autres métiers → comportement inchangé.
ALTER TABLE public.creneaux_pro
  ADD COLUMN IF NOT EXISTS capacite integer DEFAULT 1;

-- La pet-sitter autorise (ou non) des prestations qui se chevauchent dans le
-- temps, jusqu'à la capacité. Défaut = autorisé.
ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS garde_chevauchement_ok boolean DEFAULT true;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS garde_chevauchement_ok boolean DEFAULT true;
