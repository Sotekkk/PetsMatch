-- ════════════════════════════════════════════════════════════════════════
-- Audit du stockage (LECTURE SEULE) : fichiers que plus aucune ligne de la
-- base ne référence, du plus lourd au plus léger.
--
-- Principe : on relève dans TOUTES les colonnes texte / json / tableaux du
-- schéma public
--   • les URL de stockage  …/object/(public|sign|authenticated)/<bucket>/<chemin>
--   • les chemins bruts    dossier/…/fichier.ext  (documents privés)
-- puis on liste les objets de storage.objects qui n'y figurent pas.
--
-- À lancer dans l'éditeur SQL de Supabase. Rien n'est modifié : la
-- suppression se fait ensuite par l'API de stockage (Supabase interdit de
-- supprimer directement dans storage.objects), après relecture de la liste.
-- Limite : un fichier référencé hors de la base (Firestore, code, e-mail
-- déjà envoyé) apparaît comme orphelin — d'où la relecture.
-- ════════════════════════════════════════════════════════════════════════

create temp table refs_stockage (bucket text, chemin text) on commit preserve rows;

do $$
declare c record;
begin
  for c in
    select table_name, column_name
      from information_schema.columns
     where table_schema = 'public'
       and data_type in ('text', 'character varying', 'jsonb', 'json', 'ARRAY')
       and table_name in (select table_name from information_schema.tables
                           where table_schema = 'public' and table_type = 'BASE TABLE')
  loop
    -- URL complètes (publiques ou signées).
    execute format($q$
      insert into refs_stockage
      select m[1], m[2]
        from (select %1$I::text as v from public.%2$I where %1$I::text like '%%/object/%%') t,
             regexp_matches(t.v, '/object/(?:public|sign|authenticated)/([^/"\s]+)/([^"?\s,\\]+)', 'g') as m
    $q$, c.column_name, c.table_name);
    -- Chemins bruts (sans bucket).
    execute format($q$
      insert into refs_stockage
      select null, m[1]
        from (select %1$I::text as v from public.%2$I where %1$I::text ~ '[A-Za-z0-9_-]+/[^"\s]+\.[A-Za-z0-9]{2,5}') t,
             regexp_matches(t.v, '(?:^|["\s,{])([A-Za-z0-9_-]+/[^"?\s,\\}]+\.[A-Za-z0-9]{2,5})', 'g') as m
    $q$, c.column_name, c.table_name);
  end loop;
end $$;

-- URL encodées (%20…) : on compare aussi la version décodée la plus courante.
update refs_stockage set chemin = replace(chemin, '%20', ' ') where chemin like '%\%20%';

select o.bucket_id                                        as bucket,
       o.name                                             as chemin,
       round((o.metadata ->> 'size')::numeric / 1048576, 2) as taille_mo,
       o.created_at::date                                 as cree_le
  from storage.objects o
 where not exists (select 1 from refs_stockage r
                    where r.chemin = o.name and (r.bucket is null or r.bucket = o.bucket_id))
 order by (o.metadata ->> 'size')::bigint desc nulls last;

-- Total par bucket des orphelins :
-- select bucket_id, count(*), round(sum((metadata->>'size')::numeric)/1048576,1) as mo
--   from storage.objects o
--  where not exists (select 1 from refs_stockage r where r.chemin = o.name and (r.bucket is null or r.bucket = o.bucket_id))
--  group by 1 order by 3 desc;
