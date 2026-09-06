-- Phase 1 (social) — the friends activity feed needs elevation gain and
-- wall-clock elapsed time on shared runs. Both already exist locally on
-- `RunRecord` (SQLite); this extends the cloud `runs` table so CloudSyncService
-- can round-trip them. Nullable — existing rows and older app builds that don't
-- send these keys keep working.

alter table public.runs
  add column if not exists elevation_gain  double precision,
  add column if not exists elapsed_seconds integer;
