-- Entraide entre PetFriends : demande de garde/dépannage informelle entre
-- particuliers (≠ module garde PRO, pas de paiement ni de contrat). Un ami
-- demande à un autre de s'occuper d'un animal sur une période donnée,
-- l'autre accepte ou refuse depuis le chat PetFriends.
-- Filtrage applicatif (Firebase Auth + client anon), même pattern que
-- petfriends/posts_socialmedia : pas de RLS dédiée, lecture publique.

CREATE TABLE IF NOT EXISTS public.garde_entraide (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  uid_demandeur text NOT NULL,
  uid_recepteur text NOT NULL,
  demandeur_profile_id uuid,
  recepteur_profile_id uuid,
  conversation_id uuid,
  animal_id uuid,
  animal_nom text,
  date_debut date NOT NULL,
  date_fin date NOT NULL,
  message text,
  statut text NOT NULL DEFAULT 'en_attente' CHECK (statut IN ('en_attente', 'accepte', 'refuse', 'annule')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_garde_entraide_recepteur ON public.garde_entraide (uid_recepteur);
CREATE INDEX IF NOT EXISTS idx_garde_entraide_demandeur ON public.garde_entraide (uid_demandeur);
CREATE INDEX IF NOT EXISTS idx_garde_entraide_conversation ON public.garde_entraide (conversation_id);

-- Référence depuis le message de chat qui matérialise la demande (comme
-- lat/lng pour le partage de position).
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS garde_id uuid;
