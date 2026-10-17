-- Efoc — daily vlog pipeline
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- The stitching worker (worker/stitch.py) uses the service role key, so it
-- bypasses RLS. The policies below only govern what app users can do.

-- ------------------------------------------------------------
-- 1. vlogs: one stitched vlog per group per day
-- ------------------------------------------------------------

alter table public.vlogs
  add column if not exists thumbnail_path text,
  add column if not exists duration_seconds numeric;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'vlogs_group_date_key'
  ) then
    alter table public.vlogs
      add constraint vlogs_group_date_key unique (group_id, vlog_date);
  end if;
end $$;

-- Only members of the group can see its vlogs (was: any authenticated user).
-- Compared as text: vlogs.group_id is text and old rows may not be uuids.
drop policy if exists vlogs_select_auth on public.vlogs;
drop policy if exists vlogs_select_member on public.vlogs;
create policy vlogs_select_member on public.vlogs
  for select to authenticated
  using (exists (
    select 1 from public.group_members gm
    where gm.group_id::text = vlogs.group_id
      and gm.user_id = auth.uid()
  ));

-- ------------------------------------------------------------
-- 2. vlog_views: which user has watched which vlog
-- ------------------------------------------------------------
-- Drives the purple-glow / grey day dots and the group avatar ring.

create table if not exists public.vlog_views (
  user_id   uuid not null references public.profiles(id) on delete cascade,
  vlog_id   uuid not null references public.vlogs(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (user_id, vlog_id)
);

alter table public.vlog_views enable row level security;

drop policy if exists vlog_views_select_own on public.vlog_views;
create policy vlog_views_select_own on public.vlog_views
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists vlog_views_insert_own on public.vlog_views;
create policy vlog_views_insert_own on public.vlog_views
  for insert to authenticated
  with check (user_id = auth.uid());

-- ------------------------------------------------------------
-- 3. vlogs storage bucket
-- ------------------------------------------------------------
-- Private, video-sized. Paths: {group_id}/{yyyy-mm-dd}.mp4 (+ .jpg thumb).

update storage.buckets
set public = false,
    file_size_limit = 209715200, -- 200 MB
    allowed_mime_types = array['video/mp4', 'image/jpeg']
where id = 'vlogs';

drop policy if exists vlogs_read_auth on storage.objects;
drop policy if exists vlogs_read_member on storage.objects;
create policy vlogs_read_member on storage.objects
  for select to authenticated
  using (
    bucket_id = 'vlogs'
    and exists (
      select 1 from public.group_members gm
      where gm.group_id::text = (storage.foldername(name))[1]
        and gm.user_id = auth.uid()
    )
  );
