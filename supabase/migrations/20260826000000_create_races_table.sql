-- Global races database, seeded from the AIMS ICS feed (see supabase/functions/sync-races-aims).
-- Read-only from the app: only the sync Edge Function (service role) may write.

create table if not exists public.races (
  id uuid primary key default gen_random_uuid(),
  source text not null default 'aims',
  source_uid text not null,
  name text not null,
  race_date date not null,
  race_end_date date,
  location_raw text,
  city text,
  country text,
  distance_label text,
  registration_url text,
  organizer text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source, source_uid)
);

create index if not exists races_race_date_idx on public.races (race_date);
create index if not exists races_city_idx on public.races (lower(city));

alter table public.races enable row level security;

create policy "races are publicly readable"
  on public.races
  for select
  using (true);

-- Enable pg_cron/pg_net so the AIMS sync can be scheduled from Postgres.
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
