-- Les vignettes du carnet de santé (_SanteTile) affichent leur compteur via
-- Supabase Realtime (.stream()), contrairement à la liste complète qui
-- utilise une requête classique (.select()) — toute table absente de la
-- publication realtime reste bloquée sur "Aucune entrée" même quand des
-- enregistrements existent bel et bien (visibles seulement une fois la
-- liste ouverte). Repéré sur traitements ; couvre ici toutes les
-- catégories du carnet par précaution, de façon idempotente.
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['vaccinations','vermifuges','antiparasitaires','traitements','allergies','poids','visites','radios']
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE %I', t);
    END IF;
  END LOOP;
END $$;
