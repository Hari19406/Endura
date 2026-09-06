-- Phase 1 (social) — the friends activity feed reads runs of athletes the
-- signed-in user follows. Postgres OR-combines permissive SELECT policies, so
-- the existing "Users can select own runs" (auth.uid() = user_id) is untouched;
-- this just widens read access to active followers.

create policy "Followers can read followed athletes' runs"
  on public.runs
  for select
  using (
    exists (
      select 1
      from public.follows f
      where f.follower_id = auth.uid()
        and f.following_id = runs.user_id
    )
  );

-- Keyset pagination for the feed: newest-first by user.
create index if not exists runs_user_id_date_idx
  on public.runs (user_id, date desc);
