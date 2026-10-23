-- Efoc — stickers in the group chat
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- A pack belongs to one Log and its members share it: anyone in the group can
-- send any sticker in it. Only the pack's owner can delete the pack.
--
-- Blobs live in a public `stickers` bucket at
--   {group_id}/{pack_id}/{index}.webp
-- which is the same public-URL scheme thumbnails and avatars already use, so
-- the app can draw a sticker with a plain Image.network and the CDN caches it
-- forever (paths never change once written).
--
-- A sticker message keeps its own copy of the URL (messages.sticker_url) so
-- the bubble still draws after the pack is deleted — same rule as the clip and
-- vlog cards, which keep card_path.

begin;

-- ------------------------------------------------------------
-- 1. Packs and stickers
-- ------------------------------------------------------------

create table if not exists public.sticker_packs (
  id uuid primary key default gen_random_uuid(),
  -- Group ids are compared as text everywhere else in this project.
  group_id text not null,
  owner_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  tray_url text,
  created_at timestamptz not null default now()
);

create index if not exists sticker_packs_group_idx
  on public.sticker_packs (group_id);

create table if not exists public.stickers (
  id uuid primary key default gen_random_uuid(),
  pack_id uuid not null references public.sticker_packs (id) on delete cascade,
  url text not null,
  emojis text[] not null default '{}',
  position int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists stickers_pack_idx on public.stickers (pack_id);

-- ------------------------------------------------------------
-- 2. messages: a new kind
-- ------------------------------------------------------------

alter table public.messages
  add column if not exists sticker_id uuid,
  add column if not exists sticker_url text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'messages_sticker_id_fkey'
  ) then
    alter table public.messages
      add constraint messages_sticker_id_fkey foreign key (sticker_id)
      references public.stickers (id) on delete set null;
  end if;
end $$;

alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages
  add constraint messages_kind_check
  check (kind in ('text', 'clip', 'vlog', 'sticker'));

-- Text messages keep the old rule. Cards are checked on what they draw from
-- instead: a clip card needs its path, a vlog card its date, a sticker its URL.
alter table public.messages drop constraint if exists messages_content_check;
alter table public.messages
  add constraint messages_content_check check (
    case kind
      when 'text' then coalesce(btrim(text), '') <> '' or clip_id is not null
      when 'clip' then card_path is not null
      when 'vlog' then vlog_id is not null or card_date is not null
      when 'sticker' then sticker_url is not null
      else false
    end
  );

-- ------------------------------------------------------------
-- 3. RLS
-- ------------------------------------------------------------

alter table public.sticker_packs enable row level security;
alter table public.stickers enable row level security;

drop policy if exists sticker_packs_select_member on public.sticker_packs;
create policy sticker_packs_select_member on public.sticker_packs
  for select to authenticated
  using (exists (
    select 1 from public.group_members gm
    where gm.group_id::text = sticker_packs.group_id
      and gm.user_id = auth.uid()
  ));

drop policy if exists sticker_packs_insert_own on public.sticker_packs;
create policy sticker_packs_insert_own on public.sticker_packs
  for insert to authenticated
  with check (
    owner_id = auth.uid()
    and exists (
      select 1 from public.group_members gm
      where gm.group_id::text = sticker_packs.group_id
        and gm.user_id = auth.uid()
    )
  );

drop policy if exists sticker_packs_update_own on public.sticker_packs;
create policy sticker_packs_update_own on public.sticker_packs
  for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists sticker_packs_delete_own on public.sticker_packs;
create policy sticker_packs_delete_own on public.sticker_packs
  for delete to authenticated
  using (owner_id = auth.uid());

-- Stickers inherit their pack's group: members can add and remove stickers in
-- any pack they can see, so a group can keep filling a shared pack.

drop policy if exists stickers_select_member on public.stickers;
create policy stickers_select_member on public.stickers
  for select to authenticated
  using (exists (
    select 1
    from public.sticker_packs p
    join public.group_members gm on gm.group_id::text = p.group_id
    where p.id = stickers.pack_id
      and gm.user_id = auth.uid()
  ));

drop policy if exists stickers_insert_member on public.stickers;
create policy stickers_insert_member on public.stickers
  for insert to authenticated
  with check (exists (
    select 1
    from public.sticker_packs p
    join public.group_members gm on gm.group_id::text = p.group_id
    where p.id = stickers.pack_id
      and gm.user_id = auth.uid()
  ));

drop policy if exists stickers_delete_member on public.stickers;
create policy stickers_delete_member on public.stickers
  for delete to authenticated
  using (exists (
    select 1
    from public.sticker_packs p
    join public.group_members gm on gm.group_id::text = p.group_id
    where p.id = stickers.pack_id
      and gm.user_id = auth.uid()
  ));

-- ------------------------------------------------------------
-- 4. Storage bucket
-- ------------------------------------------------------------
-- Public, like thumbnails: a sticker is 10–100 KB and needs to draw instantly
-- in a list of messages, so a public URL + immutable caching beats a signed
-- URL round trip per sticker. Writes are still gated on membership.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'stickers',
  'stickers',
  true,
  1048576, -- 1 MB; WhatsApp packs cap at 500 KB, we allow headroom
  array['image/webp', 'image/png', 'image/gif', 'image/jpeg']
)
on conflict (id) do update
  set public = true,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and (
        coalesce(qual, '') ~ '''stickers'''
        or coalesce(with_check, '') ~ '''stickers'''
      )
  loop
    execute format('drop policy %I on storage.objects', p.policyname);
  end loop;
end $$;

create policy sticker_files_read_member on storage.objects
  for select to authenticated
  using (bucket_id = 'stickers');

create policy sticker_files_insert_member on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'stickers'
    and exists (
      select 1 from public.group_members gm
      where gm.group_id::text = (storage.foldername(name))[1]
        and gm.user_id = auth.uid()
    )
  );

create policy sticker_files_update_member on storage.objects
  for update to authenticated
  using (bucket_id = 'stickers')
  with check (
    bucket_id = 'stickers'
    and exists (
      select 1 from public.group_members gm
      where gm.group_id::text = (storage.foldername(name))[1]
        and gm.user_id = auth.uid()
    )
  );

create policy sticker_files_delete_member on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'stickers'
    and exists (
      select 1 from public.group_members gm
      where gm.group_id::text = (storage.foldername(name))[1]
        and gm.user_id = auth.uid()
    )
  );

commit;
