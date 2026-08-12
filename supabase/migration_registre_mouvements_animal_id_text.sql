-- registre_mouvements.animal_id : UUID → TEXT pour accepter les anciens IDs
-- courts (animal_<uid>_<timestamp>), comme deja fait pour annonces.animal_id.
-- Sans ce fix, tout insert de mouvement pour un animal a ID legacy echoue
-- silencieusement (22P02 invalid input syntax for type uuid), empechant le
-- registre entrees/sorties de refleter la cession du point de vue de
-- l'acquereur pour ces animaux.
ALTER TABLE registre_mouvements
  ALTER COLUMN animal_id TYPE TEXT USING animal_id::TEXT;
