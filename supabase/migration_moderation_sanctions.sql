-- Modération depuis les signalements (admin du site) : supprimer le contenu,
-- avertir, suspendre (durée) ou bloquer (définitif) un compte, TOUJOURS avec
-- la règle enfreinte, communiquée à la personne (notification + écran de
-- compte suspendu). Historique des sanctions par compte.
--
-- Écriture : uniquement par l'API admin (clé service). Lecture : la personne
-- concernée voit ses propres sanctions (motif affiché sur l'écran « compte
-- suspendu »).

create table if not exists public.sanctions_moderation (
  id             uuid primary key default gen_random_uuid(),
  uid            text not null,
  type           text not null check (type in ('suppression', 'avertissement', 'suspension', 'blocage')),
  regle          text not null,
  precisions     text,
  fin_le         timestamptz,          -- suspension : fin ; blocage : null (définitif)
  leve_le        timestamptz,          -- suspension levée (échéance ou admin)
  signalement_id text,
  contenu        jsonb,                -- contenu retiré (type, id, extrait) pour l'historique
  created_by     text,
  created_at     timestamptz not null default now()
);

create index if not exists idx_sanctions_uid on public.sanctions_moderation (uid, created_at desc);
create index if not exists idx_sanctions_echeance on public.sanctions_moderation (fin_le)
  where type = 'suspension' and leve_le is null;

alter table public.sanctions_moderation enable row level security;

drop policy if exists sanctions_lecture_soi on public.sanctions_moderation;
create policy sanctions_lecture_soi on public.sanctions_moderation
  for select using (uid = (auth.jwt() ->> 'sub'));
