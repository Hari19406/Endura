-- User-editable run name, set on the post-run summary screen
-- ("Morning Run", "Week 3 · Cruise Intervals", or whatever the athlete typed).
-- Nullable: runs uploaded before this migration have no title and clients fall
-- back to a workout-type label. Mirrors local SQLite `runs.title` (DB v12).

alter table public.runs
  add column if not exists title text;
