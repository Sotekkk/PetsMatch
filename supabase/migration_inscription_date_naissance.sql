-- Date de naissance saisie à l'inscription absente du profil une fois connecté :
-- elle est écrite dans users.date_of_birth, mais le profil (user_profiles, lu
-- par « Mon profil » appli et site) n'était jamais rempli —
-- create_main_profile_on_signup ne la recopie pas.
-- Règle projet : données d'inscription = profil d'édition.

-- Recopie à chaque écriture de users.date_of_birth (création du compte ou
-- correction), sur les profils « personne » du compte (particulier + profil
-- principal), sans écraser une date déjà saisie dans le profil.
create or replace function public.recopier_date_naissance_profil()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.date_of_birth is not null then
    update user_profiles
       set date_of_birth = new.date_of_birth
     where uid = new.uid
       and date_of_birth is null
       and (profile_type = 'particulier' or is_main is true);
  end if;
  return new;
end $$;

-- Nommé « zz » : passe après create_main_profile_on_signup (ordre alphabétique),
-- donc le profil existe déjà à l'insertion du compte.
drop trigger if exists zz_recopier_date_naissance_profil on public.users;
create trigger zz_recopier_date_naissance_profil
  after insert or update of date_of_birth on public.users
  for each row execute function public.recopier_date_naissance_profil();

-- Rattrapage des comptes déjà créés.
update user_profiles up
   set date_of_birth = u.date_of_birth
  from users u
 where u.uid = up.uid
   and up.date_of_birth is null
   and u.date_of_birth is not null
   and (up.profile_type = 'particulier' or up.is_main is true);
