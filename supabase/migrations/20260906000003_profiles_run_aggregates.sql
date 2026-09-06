-- Phase 4 (social) — denormalized run aggregates on `profiles`.
--
-- The raw `runs` table is RLS-private per user, so another athlete's profile
-- can't read it. These columns hold the high-level totals + PRs the app writes
-- from the owner's device on every run save, and they ride the existing
-- public-read policy on `profiles`.

alter table public.profiles
  add column if not exists total_distance_meters      bigint  not null default 0,
  add column if not exists total_runs                 integer not null default 0,
  add column if not exists total_moving_seconds       bigint  not null default 0,
  add column if not exists total_elevation_meters     bigint  not null default 0,
  add column if not exists best_5k_seconds            integer,
  add column if not exists best_10k_seconds           integer,
  add column if not exists best_half_marathon_seconds integer,
  add column if not exists stats_updated_at           timestamptz;

comment on column public.profiles.total_distance_meters is
  'Denormalized: sum of the owner''s run distances. Written client-side on run save.';
