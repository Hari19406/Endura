-- Phase 1 (social) — directed follow graph.
-- One row = "follower_id follows following_id". Immutable (no UPDATE).

create table if not exists public.follows (
  follower_id  uuid not null references auth.users (id) on delete cascade,
  following_id uuid not null references auth.users (id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint follows_no_self check (follower_id <> following_id)
);

-- Reverse lookup: "who follows X".
create index if not exists follows_following_idx on public.follows (following_id);

alter table public.follows enable row level security;

-- Follower relationships are public (needed for follower/following lists + counts).
create policy "Follows are publicly readable"
  on public.follows
  for select
  using (true);

-- You may only create / remove your own follow edges.
create policy "Users can follow as themselves"
  on public.follows
  for insert
  with check (auth.uid() = follower_id);

create policy "Users can unfollow as themselves"
  on public.follows
  for delete
  using (auth.uid() = follower_id);
