-- annonces.animal_id : UUID → TEXT pour accepter les anciens IDs courts
ALTER TABLE annonces
  ALTER COLUMN animal_id TYPE TEXT USING animal_id::TEXT;
