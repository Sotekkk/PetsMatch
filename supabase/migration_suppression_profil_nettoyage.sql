-- Suppression d'un profil (user_profiles) : ses données partent avec lui, sinon
-- elles se rattachent au prochain profil du même type créé sur le compte (les
-- listes association cherchent les animaux par compte + is_association).
-- Cas Natacha (22/10) : profil association supprimé puis recréé → anciens
-- animaux revenus, anciennes notifications / tâches visibles ailleurs.
--
-- Supprimé : notifications, événements d'agenda, tâches et plans de tâches du
-- profil ; animaux encore détenus par ce profil seul. Un animal cédé à
-- quelqu'un d'autre n'est pas touché : seule la propriété du profil est close.

create or replace function public.nettoyer_profil_supprime()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_animaux text[];
begin
  delete from notifications where profile_id = old.id::text;
  delete from agenda_events where profile_id = old.id;
  delete from taches_elevage where profile_id = old.id or eleveur_profile_id = old.id;
  delete from plan_taches where profile_id = old.id or eleveur_profile_id = old.id;

  -- Animaux du profil sans autre détenteur en cours.
  select array_agg(a.id) into v_animaux
    from animaux a
   where (a.profile_id = old.id
          -- anciennes fiches association sans profil (avant le cloisonnement)
          or (old.profile_type = 'association' and a.profile_id is null
              and a.uid_eleveur = old.uid and a.is_association is true))
     and not exists (
       select 1 from animaux_proprietes p
        where p.animal_id = a.id and p.date_fin is null
          and p.uid_proprio <> old.uid);

  update animaux_proprietes set date_fin = current_date
   where profile_id_proprio = old.id and date_fin is null;

  if v_animaux is not null then
    delete from animaux where id = any(v_animaux);
  end if;
  return old;
end $$;

drop trigger if exists trg_nettoyer_profil_supprime on public.user_profiles;
create trigger trg_nettoyer_profil_supprime
  after delete on public.user_profiles
  for each row execute function public.nettoyer_profil_supprime();

-- Cloisonnement strict (appli + site filtrent les animaux d'association sur
-- profile_id) : anciennes fiches association sans profil rattachées au profil
-- association du compte (s'il n'y en a qu'un).
update animaux a
   set profile_id = (select u.id from user_profiles u
                      where u.uid = a.uid_eleveur and u.profile_type = 'association')
 where a.is_association is true and a.profile_id is null
   and (select count(*) from user_profiles u
         where u.uid = a.uid_eleveur and u.profile_type = 'association') = 1;

-- Résidus de profils déjà supprimés (profile_id qui ne correspond plus à rien).
delete from notifications n where n.profile_id is not null and n.profile_id <> ''
  and not exists (select 1 from user_profiles u where u.id::text = n.profile_id);
delete from agenda_events e where e.profile_id is not null
  and not exists (select 1 from user_profiles u where u.id = e.profile_id);
