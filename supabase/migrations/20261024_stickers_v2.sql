-- Efoc — stickers v2: packs belong to a person, not to a Log
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- Clean slate: this drops the v1 group-scoped sticker tables and every sticker
-- message, then builds the Telegram-shaped model:
--
--   sticker_packs         a pack, owned by one user, addressed by a slug
--   stickers              its stickers
--   sticker_pack_installs the tray — what THIS user has installed
--
-- Reading a pack is open to any signed-in user (the app is invite-only and a
-- pack is shared by handing someone its link). Changing a pack is the owner's
-- alone. Installing is capped: past 8 visible packs the least recently used
-- one is archived, not deleted, and can be restored from the tray.
--
-- Sending a sticker never depends on install: messages keep their own copy of
-- the URL, so a recipient without the pack still sees it.

begin;

-- ------------------------------------------------------------
-- 1. Clean slate
-- ------------------------------------------------------------

drop table if exists public.sticker_pack_installs cascade;
drop table if exists public.stickers cascade;
drop table if exists public.sticker_packs cascade;

delete from public.messages where kind = 'sticker';

alter table public.messages drop constraint if exists messages_sticker_id_fkey;
alter table public.messages drop column if exists sticker_id;
alter table public.messages add column if not exists sticker_pack_id uuid;

-- The foreign key is added after sticker_packs exists — see section 2.

-- ------------------------------------------------------------
-- 2. Tables
-- ------------------------------------------------------------

create table public.sticker_packs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  -- What the share link carries: efoc.party/?pack=<slug>
  slug text not null unique,
  name text not null,
  tray_url text,
  created_at timestamptz not null default now()
);

create index sticker_packs_owner_idx on public.sticker_packs (owner_id);

-- Now the pack table exists, point message rows at it.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'messages_sticker_pack_id_fkey'
  ) then
    alter table public.messages
      add constraint messages_sticker_pack_id_fkey foreign key (sticker_pack_id)
      references public.sticker_packs (id) on delete set null;
  end if;
end $$;

create table public.stickers (
  id uuid primary key default gen_random_uuid(),
  pack_id uuid not null references public.sticker_packs (id) on delete cascade,
  url text not null,
  emojis text[] not null default '{}',
  position int not null default 0,
  created_at timestamptz not null default now()
);

create index stickers_pack_idx on public.stickers (pack_id);

create table public.sticker_pack_installs (
  user_id uuid not null references auth.users (id) on delete cascade,
  pack_id uuid not null references public.sticker_packs (id) on delete cascade,
  installed_at timestamptz not null default now(),
  last_used_at timestamptz not null default now(),
  archived boolean not null default false,
  primary key (user_id, pack_id)
);

create index sticker_pack_installs_tray_idx
  on public.sticker_pack_installs (user_id, archived, last_used_at desc);

-- ------------------------------------------------------------
-- 3. Install, with the cap
-- ------------------------------------------------------------

-- How many packs a tray shows before the least recently used one is archived.
create or replace function public.sticker_tray_limit()
returns int language sql immutable as $$ select 8 $$;

create or replace function public.install_sticker_pack(p_pack uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  keep int := public.sticker_tray_limit();
begin
  if uid is null then
    raise exception 'not signed in';
  end if;

  if not exists (select 1 from public.sticker_packs where id = p_pack) then
    raise exception 'no such pack';
  end if;

  insert into public.sticker_pack_installs (user_id, pack_id)
  values (uid, p_pack)
  on conflict (user_id, pack_id) do update
    set archived = false,
        last_used_at = now();

  -- Make room: archive everything except the [keep - 1] most recent others
  -- plus the pack just installed.
  update public.sticker_pack_installs i
     set archived = true
   where i.user_id = uid
     and i.archived = false
     and i.pack_id <> p_pack
     and i.pack_id in (
       select pack_id
         from public.sticker_pack_installs
        where user_id = uid
          and archived = false
          and pack_id <> p_pack
        -- Keep the [keep - 1] most recently used others; archive the rest.
        order by last_used_at desc
        offset greatest(keep - 1, 0)
     );
end;
$$;

-- Moving a pack to the front of the tray happens by using it.
create or replace function public.touch_sticker_pack(p_pack uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.sticker_pack_installs
     set last_used_at = now()
   where user_id = auth.uid()
     and pack_id = p_pack;
end;
$$;

-- A new pack lands in its owner's tray, unarchived.
create or replace function public.install_own_pack()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.sticker_pack_installs (user_id, pack_id)
  values (new.owner_id, new.id)
  on conflict (user_id, pack_id) do nothing;
  return new;
end;
$$;

drop trigger if exists sticker_packs_install_owner on public.sticker_packs;
create trigger sticker_packs_install_owner
  after insert on public.sticker_packs
  for each row execute function public.install_own_pack();

-- ------------------------------------------------------------
-- 4. RLS
-- ------------------------------------------------------------

alter table public.sticker_packs enable row level security;
alter table public.stickers enable row level security;
alter table public.sticker_pack_installs enable row level security;

drop policy if exists sticker_packs_select on public.sticker_packs;
create policy sticker_packs_select on public.sticker_packs
  for select to authenticated using (true);

drop policy if exists sticker_packs_insert_own on public.sticker_packs;
create policy sticker_packs_insert_own on public.sticker_packs
  for insert to authenticated with check (owner_id = auth.uid());

drop policy if exists sticker_packs_update_own on public.sticker_packs;
create policy sticker_packs_update_own on public.sticker_packs
  for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists sticker_packs_delete_own on public.sticker_packs;
create policy sticker_packs_delete_own on public.sticker_packs
  for delete to authenticated using (owner_id = auth.uid());

drop policy if exists stickers_select on public.stickers;
create policy stickers_select on public.stickers
  for select to authenticated using (true);

drop policy if exists stickers_insert_own on public.stickers;
create policy stickers_insert_own on public.stickers
  for insert to authenticated
  with check (exists (
    select 1 from public.sticker_packs p
    where p.id = stickers.pack_id and p.owner_id = auth.uid()
  ));

drop policy if exists stickers_delete_own on public.stickers;
create policy stickers_delete_own on public.stickers
  for delete to authenticated
  using (exists (
    select 1 from public.sticker_packs p
    where p.id = stickers.pack_id and p.owner_id = auth.uid()
  ));

-- The tray is private to its owner. Insert and update go through
-- install_sticker_pack / touch_sticker_pack, so the cap can't be bypassed.
drop policy if exists sticker_installs_select_own on public.sticker_pack_installs;
create policy sticker_installs_select_own on public.sticker_pack_installs
  for select to authenticated using (user_id = auth.uid());

drop policy if exists sticker_installs_delete_own on public.sticker_pack_installs;
create policy sticker_installs_delete_own on public.sticker_pack_installs
  for delete to authenticated using (user_id = auth.uid());

-- ------------------------------------------------------------
-- 5. Storage: {owner_id}/{pack_id}/{file}
-- ------------------------------------------------------------

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

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'stickers', 'stickers', true, 1048576,
  array['image/webp', 'image/png', 'image/gif', 'image/jpeg']
)
on conflict (id) do update
  set public = true,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists sticker_files_read on storage.objects;
create policy sticker_files_read on storage.objects
  for select to authenticated using (bucket_id = 'stickers');

drop policy if exists sticker_files_insert_own on storage.objects;
create policy sticker_files_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'stickers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists sticker_files_update_own on storage.objects;
create policy sticker_files_update_own on storage.objects
  for update to authenticated
  using (
    bucket_id = 'stickers'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'stickers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists sticker_files_delete_own on storage.objects;
create policy sticker_files_delete_own on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'stickers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- v1 files lived under {group_id}/…; nothing references them now.
delete from storage.objects where bucket_id = 'stickers';

commit;
