-- Per-run weather captured around the run (temperature, feels-like, humidity,
-- dew point, condition, observation time, source) as one JSON payload.
-- Nullable: runs uploaded before this migration, indoor/manual runs and runs
-- where the weather lookup failed have none, and clients treat that as
-- "unknown". Mirrors local SQLite `runs.weather_json` (DB v13).

alter table public.runs
  add column if not exists weather jsonb;
