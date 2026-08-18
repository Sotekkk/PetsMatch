-- Relie chaque ligne du registre sanitaire à l'enregistrement qui l'a
-- générée (ex: vaccinations.id), pour pouvoir la mettre à jour ou la
-- supprimer quand cet enregistrement est modifié/supprimé, au lieu de
-- créer une ligne orpheline à chaque fois et de ne jamais nettoyer.
ALTER TABLE registre_sanitaire
  ADD COLUMN IF NOT EXISTS source_table text,
  ADD COLUMN IF NOT EXISTS source_id text;

-- Un seul enregistrement registre par (source_table, source_id) : permet
-- un upsert direct depuis l'app/le site (créer si absent, sinon mettre à
-- jour) sans avoir à chercher la ligne existante au préalable.
CREATE UNIQUE INDEX IF NOT EXISTS registre_sanitaire_source_unique
  ON registre_sanitaire (source_table, source_id)
  WHERE source_table IS NOT NULL AND source_id IS NOT NULL;
