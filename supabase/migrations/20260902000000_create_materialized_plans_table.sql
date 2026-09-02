-- Materialised training plans: the whole plan (every week -> 7 days -> resolved
-- workouts with paces) built up front by PlanMaterializer and read (not
-- recomputed) on app open. One row per plan; ~40-80 KB of JSON in `payload`.
-- Private to each user.

create table if not exists public.materialized_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_id text not null,
  inputs_fingerprint text not null,
  built_from_vdot int,
  schema_version int not null default 1,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, plan_id)
);

create index if not exists materialized_plans_user_idx
  on public.materialized_plans (user_id);

alter table public.materialized_plans enable row level security;

create policy "own materialized plans are readable"
  on public.materialized_plans
  for select
  using (auth.uid() = user_id);

create policy "own materialized plans are insertable"
  on public.materialized_plans
  for insert
  with check (auth.uid() = user_id);

create policy "own materialized plans are updatable"
  on public.materialized_plans
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "own materialized plans are deletable"
  on public.materialized_plans
  for delete
  using (auth.uid() = user_id);

-- Keep updated_at fresh on every write.
create or replace function public.touch_materialized_plans_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists materialized_plans_touch_updated_at on public.materialized_plans;
create trigger materialized_plans_touch_updated_at
  before update on public.materialized_plans
  for each row
  execute function public.touch_materialized_plans_updated_at();
