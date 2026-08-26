-- Autorise des employés précis à APPLIQUER un protocole créé par l'élevage
-- (par défaut, un employé ne peut appliquer que ses propres protocoles).
create table if not exists plan_template_autorisations (
  id bigint generated always as identity primary key,
  template_id uuid not null references plan_templates(id) on delete cascade,
  employe_profile_id uuid not null references user_profiles(id) on delete cascade,
  created_at timestamptz default now(),
  unique (template_id, employe_profile_id)
);

create index if not exists idx_plan_template_autorisations_template
  on plan_template_autorisations(template_id);
create index if not exists idx_plan_template_autorisations_employe
  on plan_template_autorisations(employe_profile_id);

alter table plan_template_autorisations enable row level security;

drop policy if exists "plan_template_autorisations_all" on plan_template_autorisations;
create policy "plan_template_autorisations_all" on plan_template_autorisations
  for all using (true) with check (true);
