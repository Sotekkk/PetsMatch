-- Migration : périmètre des protocoles — ajout de « portée » et « locaux »
-- La page Protocoles distingue désormais : un ou plusieurs animaux
-- (individuel), une portée (portee), tout le cheptel (cheptel), une catégorie
-- d'animaux (males / femelles / gestantes / allaitantes / bebes) et les
-- locaux ou le matériel (locaux, aucun animal : une seule série de tâches).
--
-- Sans cette migration : « Locaux / matériel » s'enregistre encore en
-- « cheptel » pour un protocole Désinfection / Matériel (relu comme locaux
-- par l'appli et le site) ; « Portée » est refusée avec un message.
--
-- Reprise : les anciens protocoles Désinfection / Matériel enregistrés en
-- « cheptel » (le formulaire l'imposait) portent en réalité sur les locaux.
-- Ils restent tels quels en base : le code les lit déjà comme « locaux ».

ALTER TABLE plan_templates DROP CONSTRAINT IF EXISTS plan_templates_cible_type_check;
ALTER TABLE plan_templates ADD CONSTRAINT plan_templates_cible_type_check
  CHECK (cible_type IN ('individuel', 'portee', 'cheptel', 'males', 'femelles',
                        'gestantes', 'allaitantes', 'bebes', 'locaux'));

NOTIFY pgrst, 'reload schema';
