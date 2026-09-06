-- Activity feed polish:
--   * profiles.is_pro       — denormalized "has an active Endura Pro
--                             entitlement", written by the owner's device
--                             (same pattern as the run-aggregate columns).
--                             Drives the verified badge on feed cards / headers.
--   * runs.plan_name        — human label of the training plan a run belonged
--     runs.plan_progress      to ("5K Plan", "Week 3 / 8"), stamped at upload
--                             time for guided (non-free) runs. Both nullable.

alter table public.profiles
  add column if not exists is_pro boolean not null default false;

alter table public.runs
  add column if not exists plan_name     text,
  add column if not exists plan_progress text;
