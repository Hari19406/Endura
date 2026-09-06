-- Phase 5 (social) — drop @username, align with the Strava identity model.
--
-- Athletes are identified by `id` (internal uuid) in URLs/references and by
-- `display_name` + `city`/`country` for humans. The unique-handle idea from
-- 20260906000000 is removed. No data loss: 0 rows ever had a username set.

drop index if exists public.profiles_username_key;

alter table public.profiles
  drop constraint if exists profiles_username_format_chk;

alter table public.profiles
  drop column if exists username;
