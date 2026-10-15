-- Toilettage — suivi opérationnel d'une prestation (tableau de bord du salon).
-- Étapes horodatées sur le rendez-vous (traçabilité, rien n'est écrasé) :
--   rdv.arrivee_validee_le   (colonne existante) : animal arrivé
--   rdv.prestation_debut_le  : toilettage commencé
--   rdv.pret_le              : toilettage fini, animal prêt à récupérer
--   rdv.termine_at / statut 'termine' (existants) : animal récupéré, clôturé
--   statut 'absent'          : client non présenté (statut texte libre, aucun
--                              impact sur les rendez-vous existants)
-- Une prestation terminée n'est pas considérée comme payée (facturation
-- inchangée). Idempotent.
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS arrivee_validee_le TIMESTAMPTZ;
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS prestation_debut_le TIMESTAMPTZ;
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS pret_le TIMESTAMPTZ;

NOTIFY pgrst, 'reload schema';
