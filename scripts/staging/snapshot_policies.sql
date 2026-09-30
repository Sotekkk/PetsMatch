-- Génère un script de RETOUR ARRIÈRE : recrée toutes les policies RLS
-- actuelles (schémas public + storage) et les fonctions modifiées par les
-- migrations RLS du 30/09/2026. LECTURE SEULE.
-- Usage : psql "$PROD_DB_URL" -At -f scripts/staging/snapshot_policies.sql > rollback_rls_AAAAMMJJ.sql
-- ⚠ Le fichier produit ne doit pas être commité s'il n'est pas relu
--   (il ne contient que du SQL de structure, aucune donnée).
\set QUIET on
\pset footer off
\pset tuples_only on
\pset format unaligned

SELECT '-- Retour arrière RLS généré le ' || now();
SELECT 'BEGIN;';

-- 1. Supprimer toutes les policies présentes au moment du retour arrière.
SELECT $$DO $x$ DECLARE p record; BEGIN
  FOR p IN SELECT schemaname, tablename, policyname FROM pg_policies
           WHERE schemaname IN ('public', 'storage') LOOP
    EXECUTE format('DROP POLICY %I ON %I.%I', p.policyname, p.schemaname, p.tablename);
  END LOOP; END $x$;$$;

-- 2. Recréer les policies d'aujourd'hui.
SELECT format('CREATE POLICY %I ON %I.%I AS %s FOR %s TO %s%s%s;',
              policyname, schemaname, tablename, permissive, cmd,
              array_to_string(roles, ', '),
              CASE WHEN qual IS NOT NULL THEN ' USING (' || qual || ')' ELSE '' END,
              CASE WHEN with_check IS NOT NULL THEN ' WITH CHECK (' || with_check || ')' ELSE '' END)
FROM pg_policies
WHERE schemaname IN ('public', 'storage')
ORDER BY schemaname, tablename, policyname;

-- 3. Fonctions existantes modifiées par les migrations (définition actuelle).
SELECT pg_get_functiondef(p.oid) || ';'
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN ('users_protect_sensitive_fields', 'grant_trial_on_new_pro_profile');

-- 4. Réglages du bucket media.
SELECT format('UPDATE storage.buckets SET allowed_mime_types = %L::text[], file_size_limit = %s WHERE id = %L;',
              allowed_mime_types, coalesce(file_size_limit::text, 'NULL'), id)
FROM storage.buckets WHERE id = 'media';

SELECT 'COMMIT;';
-- Les nouvelles fonctions (pm_*) et le trigger trg_user_profiles_protege_colonnes
-- sont inoffensifs une fois les policies d'origine restaurées ; pour les
-- retirer aussi : DROP TRIGGER trg_user_profiles_protege_colonnes ON public.user_profiles;
