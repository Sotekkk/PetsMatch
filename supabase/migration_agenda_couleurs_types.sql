-- Couleurs personnalisées par type d'événement dans l'agenda (façon Google
-- Agenda) — l'utilisateur choisit une couleur par type (rdv, promenade,
-- formation…), appliquée à tous les événements de ce type.
-- Clé = type d'événement (ex. 'rdv', 'promenade'), valeur = hex '#RRGGBB'.
ALTER TABLE users ADD COLUMN IF NOT EXISTS agenda_couleurs_types JSONB DEFAULT '{}'::jsonb;
