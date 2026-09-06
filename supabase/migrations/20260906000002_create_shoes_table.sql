-- Phase 1 (social) — shoe locker / gear tracking.
-- Distances stored in metres (integer-friendly numeric). `max_distance_meters`
-- is the retirement target the UI mileage bar fills toward (default 800 km,
-- the common road-shoe ceiling).

create table if not exists public.shoes (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users (id) on delete cascade,
  brand               text not null,
  model               text not null,
  nickname            text,
  distance_meters     numeric not null default 0 check (distance_meters >= 0),
  max_distance_meters numeric not null default 800000 check (max_distance_meters > 0),
  is_default          boolean not null default false,
  is_retired          boolean not null default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists shoes_user_idx on public.shoes (user_id);

-- At most one default shoe per user.
create unique index if not exists shoes_one_default_per_user
  on public.shoes (user_id)
  where is_default;

alter table public.shoes enable row level security;

-- Readable by the owner, or by anyone when the owner's profile is public
-- (so the Gear tab renders on a public athlete profile).
create policy "Shoes readable for self or public profiles"
  on public.shoes
  for select
  using (
    auth.uid() = user_id
    or exists (
      select 1 from public.profiles p
      where p.id = shoes.user_id and p.is_public = true
    )
  );

create policy "Users manage own shoes (insert)"
  on public.shoes
  for insert
  with check (auth.uid() = user_id);

create policy "Users manage own shoes (update)"
  on public.shoes
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users manage own shoes (delete)"
  on public.shoes
  for delete
  using (auth.uid() = user_id);

-- Keep updated_at fresh.
create or replace function public.touch_shoes_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists shoes_touch_updated_at on public.shoes;
create trigger shoes_touch_updated_at
  before update on public.shoes
  for each row
  execute function public.touch_shoes_updated_at();
