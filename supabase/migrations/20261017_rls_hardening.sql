-- Efoc — RLS hardening before inviting friends
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- Replaces the "any authenticated user can read" policies from solo dev with
-- group-membership checks. group_id columns are compared as text, like the
-- vlog pipeline migration: clips.group_id is text and old rows may not be
-- uuids (e.g. the mock 'personal' id), so casting them to uuid would throw.
--
-- The stitching worker (worker/stitch.py) uses the service role key, so it
-- bypasses RLS and is unaffected.

begin;

-- ------------------------------------------------------------
-- 1. clips
-- ------------------------------------------------------------

-- Drop every existing SELECT policy, not just the known name: policies are
-- OR'ed, so one leftover `using (true)` would keep the table wide open.
do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'clips' and cmd = 'SELECT'
  loop
    execute format('drop policy %I on public.clips', p.policyname);
  end loop;
end $$;

create policy clips_select_member on public.clips
  for select to authenticated
  using (exists (
    select 1 from public.group_members gm
    where gm.group_id::text = clips.group_id
      and gm.user_id = auth.uid()
  ));

-- Two INSERT policies did the same check; replace both with one that also
-- requires membership of the target group.
drop policy if exists "Users can insert their own clips" on public.clips;
drop policy if exists clips_insert_own on public.clips;
create policy clips_insert_own on public.clips
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.group_members gm
      where gm.group_id::text = clips.group_id
        and gm.user_id = auth.uid()
    )
  );

-- ClipService.uploadClip upserts on (user_id, group_id, hour_of_day,
-- recorded_on), so a retake hits ON CONFLICT DO UPDATE, which needs this.
drop policy if exists clips_update_own on public.clips;
create policy clips_update_own on public.clips
  for update to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.group_members gm
      where gm.group_id::text = clips.group_id
        and gm.user_id = auth.uid()
    )
  );

-- clips_delete_own (user_id = auth.uid()) is unchanged.

-- ------------------------------------------------------------
-- 2. comments and reactions on clips
-- ------------------------------------------------------------
-- Readable by members of the clip's group.

do $$
declare p record;
begin
  for p in
    select tablename, policyname from pg_policies
    where schemaname = 'public'
      and tablename in ('comments', 'reactions')
      and cmd = 'SELECT'
  loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

create policy comments_select_member on public.comments
  for select to authenticated
  using (exists (
    select 1
    from public.clips c
    join public.group_members gm on gm.group_id::text = c.group_id
    where c.id = comments.clip_id
      and gm.user_id = auth.uid()
  ));

create policy reactions_select_member on public.reactions
  for select to authenticated
  using (exists (
    select 1
    from public.clips c
    join public.group_members gm on gm.group_id::text = c.group_id
    where c.id = reactions.clip_id
      and gm.user_id = auth.uid()
  ));

-- *_insert_own / *_delete_own (user_id = auth.uid()) are unchanged.

-- ------------------------------------------------------------
-- 3. messages and message_reactions (group chat)
-- ------------------------------------------------------------
-- Added after the 2026-09-24 schema snapshot, so the existing policies are
-- unknown here: drop them all and recreate the set ChatService needs.
-- group_id is cast to text on both sides so this works whether the column
-- is text or uuid.

do $$
declare p record;
begin
  if to_regclass('public.messages') is null then
    raise notice 'public.messages not found, skipping chat policies';
    return;
  end if;

  for p in
    select tablename, policyname from pg_policies
    where schemaname = 'public'
      and tablename in ('messages', 'message_reactions')
  loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;

  alter table public.messages enable row level security;

  create policy messages_select_member on public.messages
    for select to authenticated
    using (exists (
      select 1 from public.group_members gm
      where gm.group_id::text = messages.group_id::text
        and gm.user_id = auth.uid()
    ));

  create policy messages_insert_own on public.messages
    for insert to authenticated
    with check (
      user_id = auth.uid()
      and exists (
        select 1 from public.group_members gm
        where gm.group_id::text = messages.group_id::text
          and gm.user_id = auth.uid()
      )
    );

  create policy messages_delete_own on public.messages
    for delete to authenticated
    using (user_id = auth.uid());

  if to_regclass('public.message_reactions') is null then
    raise notice 'public.message_reactions not found, skipping';
    return;
  end if;

  alter table public.message_reactions enable row level security;

  create policy message_reactions_select_member on public.message_reactions
    for select to authenticated
    using (exists (
      select 1
      from public.messages m
      join public.group_members gm on gm.group_id::text = m.group_id::text
      where m.id = message_reactions.message_id
        and gm.user_id = auth.uid()
    ));

  create policy message_reactions_insert_own on public.message_reactions
    for insert to authenticated
    with check (
      user_id = auth.uid()
      and exists (
        select 1
        from public.messages m
        join public.group_members gm on gm.group_id::text = m.group_id::text
        where m.id = message_reactions.message_id
          and gm.user_id = auth.uid()
      )
    );

  create policy message_reactions_delete_own on public.message_reactions
    for delete to authenticated
    using (user_id = auth.uid());
end $$;

-- ------------------------------------------------------------
-- 4. clips and thumbnails storage buckets
-- ------------------------------------------------------------
-- Paths: {group_id}/{user_id}/HH-yyyy-mm-dd.{mp4,webm,mov} in clips and
-- the same path with .jpg in thumbnails.
--   read   -> member of the group in segment 1
--   write  -> segment 2 is your own uid, and you're a member of segment 1
-- Uploads use upsert: true, which needs SELECT + INSERT + UPDATE.
--
-- Drop every existing policy that mentions either bucket (names for the
-- thumbnails bucket and any public .jpg read on clips aren't in the snapshot).

do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and (
        coalesce(qual, '') ~ '''(clips|thumbnails)'''
        or coalesce(with_check, '') ~ '''(clips|thumbnails)'''
      )
  loop
    execute format('drop policy %I on storage.objects', p.policyname);
  end loop;
end $$;

create policy clip_files_read_member on storage.objects
  for select to authenticated
  using (
    bucket_id in ('clips', 'thumbnails')
    and exists (
      select 1 from public.group_members gm
      where gm.group_id::text = (storage.foldername(name))[1]
        and gm.user_id = auth.uid()
    )
  );

create policy clip_files_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id in ('clips', 'thumbnails')
    and (storage.foldername(name))[2] = auth.uid()::text
    and exists (
      select 1 from public.group_members gm
      where gm.group_id::text = (storage.foldername(name))[1]
        and gm.user_id = auth.uid()
    )
  );

create policy clip_files_update_own on storage.objects
  for update to authenticated
  using (
    bucket_id in ('clips', 'thumbnails')
    and (storage.foldername(name))[2] = auth.uid()::text
  )
  with check (
    bucket_id in ('clips', 'thumbnails')
    and (storage.foldername(name))[2] = auth.uid()::text
    and exists (
      select 1 from public.group_members gm
      where gm.group_id::text = (storage.foldername(name))[1]
        and gm.user_id = auth.uid()
    )
  );

-- NOTE: the thumbnails bucket is public (ClipService.publicThumbnailUrl uses
-- getPublicUrl), and public-bucket URLs skip RLS entirely. The read policy
-- above only takes effect once the bucket is made private and the app
-- switches to signed URLs. Not flipped here because it would break the grid.

-- ------------------------------------------------------------
-- 5. Sanity check: warn about anything still open to every user
-- ------------------------------------------------------------

do $$
declare p record;
begin
  for p in
    select schemaname, tablename, policyname, cmd from pg_policies
    where (
        (schemaname = 'public'
         and tablename in ('clips', 'comments', 'reactions',
                           'messages', 'message_reactions'))
        or (schemaname = 'storage' and tablename = 'objects'
            and coalesce(qual, '') ~ '''(clips|thumbnails)''')
      )
      and cmd in ('SELECT', 'ALL')
      and coalesce(qual, 'true') in ('true', '(true)')
  loop
    raise warning 'still open: %.% policy % (%)',
      p.schemaname, p.tablename, p.policyname, p.cmd;
  end loop;
end $$;

commit;
