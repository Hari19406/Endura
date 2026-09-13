-- Plan history: a lightweight summary row snapshotted whenever the athlete's
-- active plan is retired — either torn down explicitly (EngineMemoryService.
-- resetCurrentPlan) or replaced by a new one (EngineMemoryService.saveRacePlan
-- with archivePrevious: true, its default). Read-only append log for the
-- "Previous Plans" section; the full plan shape lives in `snapshot_data` for
-- any future deep-dive, but the summary columns are what the list UI reads.
-- Private to each user, insert-only from the client (no update/delete policy
-- — history rows are immutable once written).

create table if not exists public.plan_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_name text not null,
  plan_type text not null,
  duration_weeks int not null,
  total_distance_km double precision not null,
  completed_distance_km double precision not null default 0,
  started_at timestamptz not null,
  ended_at timestamptz not null default now(),
  status text not null default 'completed' check (status in ('completed', 'archived')),
  snapshot_data jsonb,
  created_at timestamptz not null default now()
);

create index if not exists plan_history_user_ended_at_idx
  on public.plan_history (user_id, ended_at desc);

alter table public.plan_history enable row level security;

create policy "own plan history is readable"
  on public.plan_history
  for select
  using (auth.uid() = user_id);

create policy "own plan history is insertable"
  on public.plan_history
  for insert
  with check (auth.uid() = user_id);
