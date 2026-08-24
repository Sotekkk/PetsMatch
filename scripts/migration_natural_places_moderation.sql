-- Migration : ajout des lieux naturels a la main (avec photo) + validation admin
-- A executer dans Supabase SQL editor.

alter table natural_places
  add column if not exists statut text not null default 'valide',
  add column if not exists adresse text,
  add column if not exists submitted_by_uid text,
  add column if not exists submitted_by_profile_id uuid,
  add column if not exists rejection_reason text;

alter table natural_places drop constraint if exists natural_places_statut_check;
alter table natural_places
  add constraint natural_places_statut_check
  check (statut in ('valide', 'en_attente', 'refuse'));

-- Les policies RLS actuelles bloquent tout insert/update depuis la cle anon
-- (verifie : meme le toggle "equipements" existant echoue silencieusement).
-- On aligne natural_places sur le reste du projet (Firebase gere l'auth,
-- Supabase sert juste de base de donnees, la securite d'ecriture est geree
-- cote application, pas via auth.uid() qui est toujours null ici).
drop policy if exists "natural_places_select_all" on natural_places;
create policy "natural_places_select_all" on natural_places
  for select using (true);

drop policy if exists "natural_places_insert_all" on natural_places;
create policy "natural_places_insert_all" on natural_places
  for insert with check (true);

drop policy if exists "natural_places_update_all" on natural_places;
create policy "natural_places_update_all" on natural_places
  for update using (true) with check (true);

-- Signalement d'equipements (eau potable, parking, fontaine...) avec photo
-- obligatoire, valide par un admin avant application sur natural_places.
create table if not exists natural_place_amenity_suggestions (
  id uuid primary key default gen_random_uuid(),
  place_id uuid not null references natural_places(id) on delete cascade,
  field text not null check (field in (
    'has_eau', 'has_parking', 'has_fontaine', 'has_poubelle',
    'parcours_ombre', 'baignade_possible'
  )),
  value boolean not null,
  photo_url text not null,
  submitted_by_uid text,
  submitted_by_profile_id uuid,
  statut text not null default 'en_attente' check (statut in ('en_attente', 'valide', 'refuse')),
  rejection_reason text,
  created_at timestamptz not null default now()
);

alter table natural_place_amenity_suggestions enable row level security;

drop policy if exists "amenity_suggestions_select_all" on natural_place_amenity_suggestions;
create policy "amenity_suggestions_select_all" on natural_place_amenity_suggestions
  for select using (true);

drop policy if exists "amenity_suggestions_insert_all" on natural_place_amenity_suggestions;
create policy "amenity_suggestions_insert_all" on natural_place_amenity_suggestions
  for insert with check (true);

drop policy if exists "amenity_suggestions_update_all" on natural_place_amenity_suggestions;
create policy "amenity_suggestions_update_all" on natural_place_amenity_suggestions
  for update using (true) with check (true);

-- Photos ajoutees par les utilisateurs sur un lieu existant : validees par un
-- admin avant d'etre ajoutees a la galerie publique (et eventuellement de
-- devenir la photo de couverture si le lieu n'en a pas encore).
create table if not exists natural_place_photo_suggestions (
  id uuid primary key default gen_random_uuid(),
  place_id uuid not null references natural_places(id) on delete cascade,
  photo_url text not null,
  submitted_by_uid text,
  submitted_by_profile_id uuid,
  statut text not null default 'en_attente' check (statut in ('en_attente', 'valide', 'refuse')),
  rejection_reason text,
  created_at timestamptz not null default now()
);

alter table natural_place_photo_suggestions enable row level security;

drop policy if exists "photo_suggestions_select_all" on natural_place_photo_suggestions;
create policy "photo_suggestions_select_all" on natural_place_photo_suggestions
  for select using (true);

drop policy if exists "photo_suggestions_insert_all" on natural_place_photo_suggestions;
create policy "photo_suggestions_insert_all" on natural_place_photo_suggestions
  for insert with check (true);

drop policy if exists "photo_suggestions_update_all" on natural_place_photo_suggestions;
create policy "photo_suggestions_update_all" on natural_place_photo_suggestions
  for update using (true) with check (true);

-- Badge distance/duree pour les balades/parcours (forets, lacs, rivieres).
alter table natural_places
  add column if not exists distance text,
  add column if not exists duree text;
