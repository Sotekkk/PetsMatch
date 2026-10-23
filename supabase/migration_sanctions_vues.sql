-- Avertissements consultables par l'utilisateur (Paramètres → Connexion et
-- sécurité → Avertissements, appli + site) : `vue_le` alimente la bulle
-- rouge tant que la personne n'a pas ouvert la page.
--
-- Écriture des sanctions toujours réservée à l'API admin (clé service) : la
-- personne ne peut que marquer SES sanctions comme vues, via la fonction
-- ci-dessous (pas de policy UPDATE sur la table).
-- À lancer après migration_moderation_sanctions.sql. Idempotent.

begin;

-- Les sanctions déjà prononcées avant cette migration ne déclenchent pas de
-- bulle rouge (la personne a déjà reçu la notification à l'époque). Rattrapage
-- au seul ajout de la colonne : une relance ne marque pas les nouvelles.
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'sanctions_moderation'
                    and column_name = 'vue_le') then
    alter table public.sanctions_moderation add column vue_le timestamptz;
    update public.sanctions_moderation set vue_le = created_at;
  end if;
end $$;

create or replace function public.marquer_sanctions_vues()
returns void
language sql
security definer
set search_path = public
as $$
  update public.sanctions_moderation
     set vue_le = now()
   where uid = (auth.jwt() ->> 'sub')
     and vue_le is null;
$$;

revoke all on function public.marquer_sanctions_vues() from public;
grant execute on function public.marquer_sanctions_vues() to anon, authenticated;

commit;
