-- Feed/friends' activities render splits + a coarse elevation/pace chart in
-- ActivityDetailScreen via ActivityDetail.fromFeedRun. Until now the cloud
-- `runs` table carried only summary fields (distance, average pace,
-- elevation *gain* as a single total) — never the per-km breakdown — so
-- every Feed-hydrated activity had an empty KILOMETRE SPLITS card and no
-- elevation/pace charts, even though the recording device had this data
-- locally the whole time. This adds a compact `splits` column
-- (`[{km, seconds, elev?, hr?}, ...]`, one small object per km — a handful
-- of entries per run, not the full GPS/telemetry trace) so CloudSyncService
-- can upload what it already derives locally, and FeedRun/ActivityDetail can
-- read it back. Nullable — existing rows and older app builds that don't
-- send this key keep working exactly as before.

alter table public.runs
  add column if not exists splits jsonb;
