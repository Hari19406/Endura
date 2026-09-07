-- Activity feed comments. One row = one comment on a run.
--
-- Note: `public.runs.id` is a `bigint` identity column (not uuid), so `run_id`
-- is bigint here. `user_id` references `auth.users` to match `runs`/`follows`
-- (every commenter also has a `public.profiles` row, joined app-side for the
-- avatar/name).

create table if not exists public.activity_comments (
  id         uuid primary key default gen_random_uuid(),
  run_id     bigint not null references public.runs (id) on delete cascade,
  user_id    uuid   not null references auth.users (id) on delete cascade,
  comment    text   not null check (char_length(comment) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists activity_comments_run_id_idx
  on public.activity_comments (run_id, created_at);

alter table public.activity_comments enable row level security;

-- Readable when you can see the underlying run: you own it, or you follow its
-- owner (mirrors the runs SELECT policies).
create policy "Comments readable to run viewers"
  on public.activity_comments
  for select
  using (
    exists (
      select 1
      from public.runs r
      where r.id = activity_comments.run_id
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

-- You may only post as yourself, and only on a run you can see.
create policy "Users can comment as themselves on visible runs"
  on public.activity_comments
  for insert
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.runs r
      where r.id = activity_comments.run_id
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

-- You may delete your own comments.
create policy "Users can delete own comments"
  on public.activity_comments
  for delete
  using (user_id = auth.uid());
