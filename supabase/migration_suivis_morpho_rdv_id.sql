-- Rattache un suivi morphologique au rendez-vous pendant lequel il a été
-- réalisé (facultatif — les suivis créés en dehors d'un RDV, ex. saisie
-- libre depuis "Mes suivis", n'ont pas de rdv_id). Permet, depuis la carte
-- RDV, de retrouver directement le suivi déjà enregistré au lieu d'en
-- recréer un nouveau à chaque fois.
alter table suivis_morpho
  add column if not exists rdv_id uuid references rdv(id) on delete set null;
