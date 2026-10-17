-- Efoc — seen / unread tracking
--
-- Run once in the Supabase SQL Editor, after 20261017_rls_hardening.sql.
-- Safe to re-run.
--
-- Drives:
--   * the "new" hint in the group dropdown and the dot on the group pill
--   * the today/day-dot highlight for unseen clips
--   * greyed-out thumbnails for clips you've already watched
--   * the chat red dot (was in-memory only, so it came back on every restart)

-- ------------------------------------------------------------
-- 1. clip_views: which user has watched which clip
-- ------------------------------------------------------------

create table if not exists public.clip_views (
  user_id   uuid not null references public.profiles(id) on delete cascade,
  clip_id   uuid not null references public.clips(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (user_id, clip_id)
);

alter table public.clip_views enable row level security;

drop policy if exists clip_views_select_own on public.clip_views;
create policy clip_views_select_own on public.clip_views
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists clip_views_insert_own on public.clip_views;
create policy clip_views_insert_own on public.clip_views
  for insert to authenticated
  with check (user_id = auth.uid());

-- ------------------------------------------------------------
-- 2. chat_reads: when each user last read each group's chat
-- ------------------------------------------------------------
-- group_id is text, like clips and vlogs.

create table if not exists public.chat_reads (
  user_id      uuid not null references public.profiles(id) on delete cascade,
  group_id     text not null,
  last_read_at timestamptz not null default now(),
  primary key (user_id, group_id)
);

alter table public.chat_reads enable row level security;

drop policy if exists chat_reads_select_own on public.chat_reads;
create policy chat_reads_select_own on public.chat_reads
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists chat_reads_insert_own on public.chat_reads;
create policy chat_reads_insert_own on public.chat_reads
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists chat_reads_update_own on public.chat_reads;
create policy chat_reads_update_own on public.chat_reads
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ------------------------------------------------------------
-- 3. RPCs
-- ------------------------------------------------------------
-- All security invoker, so the caller's RLS applies: you only ever count
-- clips and messages in groups you're a member of.

-- Stamps "read now" with the server clock (device clocks drift).
create or replace function public.mark_chat_read(gid text)
returns void
language sql
security invoker
as $$
  insert into public.chat_reads (user_id, group_id, last_read_at)
  values (auth.uid(), gid, now())
  on conflict (user_id, group_id) do update set last_read_at = now();
$$;

-- Groups with a message from someone else newer than your last read.
create or replace function public.unread_chat_groups()
returns setof text
language sql
stable
security invoker
as $$
  select distinct m.group_id::text
  from public.messages m
  left join public.chat_reads r
    on r.user_id = auth.uid() and r.group_id = m.group_id::text
  where m.user_id <> auth.uid()
    and m.created_at > coalesce(r.last_read_at, '-infinity'::timestamptz);
$$;

-- Clips from other members you haven't watched yet, per group and day.
create or replace function public.unseen_clip_counts(since date)
returns table (group_id text, recorded_on date, unseen integer)
language sql
stable
security invoker
as $$
  select c.group_id, c.recorded_on, count(*)::int
  from public.clips c
  where c.recorded_on >= since
    and c.user_id <> auth.uid()
    and not exists (
      select 1 from public.clip_views v
      where v.clip_id = c.id and v.user_id = auth.uid()
    )
  group by c.group_id, c.recorded_on;
$$;

grant execute on function public.mark_chat_read(text) to authenticated;
grant execute on function public.unread_chat_groups() to authenticated;
grant execute on function public.unseen_clip_counts(date) to authenticated;

-- ------------------------------------------------------------
-- 4. clips bucket: allow webm
-- ------------------------------------------------------------
-- Browser recordings (Chrome / Android PWA) are webm. They used to be
-- uploaded labelled as video/mp4 because the blob URL had no extension.

update storage.buckets
set allowed_mime_types = array['video/mp4', 'video/quicktime', 'video/webm']
where id = 'clips';
