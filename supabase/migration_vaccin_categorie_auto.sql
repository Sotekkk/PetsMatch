-- Vaccin saisi avec la catégorie « Autre » (ou vide) alors que son nom est un
-- type connu (ex. « Leptospirose (L4) ») : la catégorie est déduite du nom.
-- Sans ça, le rappel automatique ne reconnaît pas le vaccin refait et continue
-- de rappeler l'ancien (cas Vaïna : vaccins du 01/10 classés « Autre »).
-- Liste = lib/data/vaccin_types.dart / website/src/lib/vaccinTypes.ts.

create or replace function public.vaccin_categorie_depuis_nom(p_vaccin text)
returns text language sql immutable as $$
  select t.cat from (values
    ('Rage'),
    ('CHPPI (Carré, Hépatite, Parvovirose, Parainfluenza)'),
    ('Leptospirose (L4)'),
    ('Toux du chenil (Bordetella)'),
    ('Piroplasmose'),
    ('Typhus (panleucopénie)'),
    ('Coryza'),
    ('Leucose (FeLV)'),
    ('PIF (coronavirus félin)'),
    ('Myxomatose'),
    ('VHD (maladie hémorragique)'),
    ('Grippe équine'),
    ('Tétanos')
  ) as t(cat)
  where lower(trim(p_vaccin)) = lower(t.cat)
  limit 1
$$;

create or replace function public.vaccinations_categorie_auto()
returns trigger language plpgsql as $$
declare v_cat text;
begin
  if new.categorie is null or trim(new.categorie) = '' or lower(trim(new.categorie)) = 'autre' then
    v_cat := public.vaccin_categorie_depuis_nom(new.vaccin);
    if v_cat is not null then new.categorie := v_cat; end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_vaccinations_categorie_auto on public.vaccinations;
create trigger trg_vaccinations_categorie_auto
  before insert or update of vaccin, categorie on public.vaccinations
  for each row execute function public.vaccinations_categorie_auto();

-- Réparation des lignes existantes.
update public.vaccinations
   set categorie = public.vaccin_categorie_depuis_nom(vaccin)
 where (categorie is null or trim(categorie) = '' or lower(trim(categorie)) = 'autre')
   and public.vaccin_categorie_depuis_nom(vaccin) is not null;
