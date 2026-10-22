-- Forum : « Animal concerné » à plusieurs espèces (ou toutes) + race facultative.
-- animal_type reste renseigné quand une seule espèce est cochée (couleur,
-- anciens sujets). Appli : forum_page.dart ; site : forum/[categorie].
alter table public.forum_sujets add column if not exists animal_types text[];
alter table public.forum_sujets add column if not exists race text;

-- Anciens sujets : animal_types repris d'animal_type.
update public.forum_sujets set animal_types = array[animal_type]
 where animal_types is null and animal_type is not null and animal_type <> '';
