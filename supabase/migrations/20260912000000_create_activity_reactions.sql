-- Activity feed reactions ("cheers"). One row = one athlete's cheer on one
-- run. At most one reaction per (run, user) — toggling un-cheers by deleting
-- the row rather than storing a boolean, so COUNT(*) is always the live tally.
--
-- Mirrors activity_comments' visibility model: `public.runs.id` is bigint, so
-- `run_id` is bigint here too; `user_id` references `auth.users` to match
-- `runs`/`follows`/`activity_comments`.

create table if not exists public.activity_reactions (
  id         uuid primary key default gen_random_uuid(),
  run_id     bigint not null references public.runs (id) on delete cascade,
  user_id    uuid   not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (run_id, user_id)
);

create index if not exists activity_reactions_run_id_idx
  on public.activity_reactions (run_id);

alter table public.activity_reactions enable row level security;

-- Readable when you can see the underlying run: you own it, or you follow its
-- owner (mirrors activity_comments' SELECT policy).
create policy "Reactions readable to run viewers"
  on public.activity_reactions
  for select
  using (
    exists (
      select 1
      from public.runs r
      where r.id = activity_reactions.run_id
        and (
          r.user_id = auth.uid()
          or exists (
            select 1 from public.follows f
            where f.follower_id = auth.uid()
              and f.following_id = r.user_id
          )
        )
    )
  );

-- You may only react as yourself, and only on a run you can see.
create policy "Users can react as themselves on visible runs"
  on public.activity_reactions
  for insert
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.runs r
      where r.id = activity_reactions.run_id
        and (
          r.user_id = auth.uid()
          or exists (
            select 1 from public.follows f
            where f.follower_id = auth.uid()
              and f.following_id = r.user_id
          )
        )
    )
  );

-- You may remove your own reaction (un-cheer).
create policy "Users can delete own reaction"
  on public.activity_reactions
  for delete
  using (user_id = auth.uid());
