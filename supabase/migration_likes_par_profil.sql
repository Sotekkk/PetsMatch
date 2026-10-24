-- ════════════════════════════════════════════════════════════════════════
-- « J'aime » des annonces : un par PROFIL (et non plus un par compte).
--
-- Bug : l'appli et le site affichent les « j'aime » du profil actif, mais
-- la base n'en acceptait qu'un par compte et par annonce (tous profils
-- confondus). Un « j'aime » posé depuis un autre profil (ex. cogérante sous
-- le profil de l'élevage, ou profil particulier) rendait le cœur vide ET
-- impossible à cocher : l'insertion était refusée comme doublon.
--
-- Correctif : l'ancienne contrainte d'unicité (sans profile_id) est retirée,
-- remplacée par une unicité par profil. Aucune donnée n'est modifiée
-- (l'ancienne règle était plus stricte : pas de doublon possible).
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

DO $$
DECLARE r record;
BEGIN
  -- Contraintes / index uniques portant sur le compte + l'annonce, sans le profil.
  FOR r IN
    SELECT i.indexrelid::regclass::text AS idx, c.conname
      FROM pg_index i
      LEFT JOIN pg_constraint c ON c.conindid = i.indexrelid AND c.conrelid = i.indrelid
     WHERE i.indrelid = 'public.likes'::regclass
       AND i.indisunique
       AND pg_get_indexdef(i.indexrelid) ILIKE '%user_uid%'
       AND pg_get_indexdef(i.indexrelid) ILIKE '%annonce_id%'
       AND pg_get_indexdef(i.indexrelid) NOT ILIKE '%profile_id%'
  LOOP
    IF r.conname IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.likes DROP CONSTRAINT %I', r.conname);
    ELSE
      EXECUTE format('DROP INDEX %s', r.idx);
    END IF;
    RAISE NOTICE 'Unicité par compte retirée : %', coalesce(r.conname, r.idx);
  END LOOP;

  -- La table garde une clé primaire (colonne id).
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.likes'::regclass AND contype = 'p')
     AND EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'likes' AND column_name = 'id') THEN
    ALTER TABLE public.likes ADD PRIMARY KEY (id);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_likes_par_profil
  ON public.likes (user_uid, coalesce(profile_id::text, ''), annonce_id, coalesce(bebe_index, -1));

COMMIT;
