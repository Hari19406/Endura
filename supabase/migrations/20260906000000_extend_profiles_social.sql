-- Phase 1 (social) — extend the existing `profiles` table with public athlete
-- identity fields and open up read access for public profiles.
--
-- `profiles` already exists in the remote DB (see remote migrations
-- 20260621082628 onward). Rows are created by the app during onboarding — there
-- is no auth.users trigger — so every new column here is nullable / defaulted so
-- existing inserts keep working.

-- Case-insensitive unique usernames.
create extension if not exists citext with schema extensions;

alter table public.profiles
  add column if not exists username      extensions.citext,
  add column if not exists display_name  text,
  add column if not exists avatar_url    text,
  add column if not exists bio           text,
  add column if not exists city          text,
  add column if not exists country       text,
  add column if not exists is_public     boolean not null default true;

-- Username: 3–30 chars, alphanumeric + underscore, unique when set.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_username_format_chk'
  ) then
    alter table public.profiles
      add constraint profiles_username_format_chk
      check (username is null or username ~ '^[A-Za-z0-9_]{3,30}$');
  end if;
end $$;

create unique index if not exists profiles_username_key
  on public.profiles (username)
  where username is not null;

-- Seed display_name from the existing first_name for current users.
update public.profiles
   set display_name = first_name
 where display_name is null
   and first_name is not null;

-- ── RLS: allow reading public profiles, keep writes self-only ────────────────
drop policy if exists "Users can select own profile" on public.profiles;

create policy "Public profiles are readable"
  on public.profiles
  for select
  using (is_public = true or auth.uid() = id);

-- insert / update / delete policies from the earlier migrations are unchanged
-- (all scoped to auth.uid() = id).
