-- Clients sans appli (fichier clients du pro : clinique, toiletteur,
-- maréchal-ferrant, ostéopathe, éducateur — table clients_clinique) :
-- rattachement au compte PetsMatch créé ensuite avec la même adresse e-mail,
-- validé par le propriétaire (étape 2 des patients clinique).
--  • clients_clinique.uid_lie / profile_lie_id (existants) : compte rattaché ;
--  • clients_clinique.rattachement_refuse_le : le propriétaire a refusé (plus
--    de proposition).
-- À l'acceptation (route /api/clients/rattachement, service role) : chaque
-- animal du client passe au propriétaire (animaux_proprietes principal,
-- uid_proprietaire), le professionnel garde son accès (animal_access), les
-- rendez-vous à son adresse sont rattachés à son compte. Idempotent.
ALTER TABLE public.clients_clinique ADD COLUMN IF NOT EXISTS rattachement_refuse_le TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS clients_clinique_email_idx ON public.clients_clinique (lower(email));

NOTIFY pgrst, 'reload schema';
