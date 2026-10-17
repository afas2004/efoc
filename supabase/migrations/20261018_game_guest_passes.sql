-- Efoc — one-time guest passes for a card-game table
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- A member at a table makes a pass; the link efoc.party/play?pass=CODE lets
-- one person in, with just a name, to that table only. The guest-token
-- Edge Function redeems it and mints a Firebase token for "guest-<uuid>"
-- with claims { guest_room, guest_until }. The guest never gets a Supabase
-- account, so they can't see any Log, clip or chat.
--
-- One use: the first browser to redeem it owns it (device_hash); the same
-- browser can come back (page refresh) until it expires, nobody else can.

create table if not exists public.game_guest_passes (
  code         text primary key,
  room_id      text not null check (room_id ~ '^[A-Za-z0-9_-]{1,64}$'),
  group_id     uuid not null references public.groups(id) on delete cascade,
  game_id      text not null check (game_id ~ '^[a-z0-9_-]{1,32}$'),
  created_by   uuid not null default auth.uid()
               references public.profiles(id) on delete cascade,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '2 hours',
  redeemed_at  timestamptz,
  device_hash  text,
  guest_uid    text,
  guest_name   text
);

create index if not exists game_guest_passes_creator_idx
  on public.game_guest_passes (created_by, created_at desc);

alter table public.game_guest_passes enable row level security;

-- Members make passes for their own Log's tables. The code, expiry and
-- redemption columns are left to their defaults / the Edge Function.
drop policy if exists guest_passes_insert_member on public.game_guest_passes;
create policy guest_passes_insert_member on public.game_guest_passes
  for insert to authenticated
  with check (
    created_by = auth.uid()
    and redeemed_at is null and device_hash is null and guest_uid is null
    and expires_at <= now() + interval '2 hours 1 minute'
    and exists (
      select 1 from public.group_members gm
      where gm.group_id = game_guest_passes.group_id
        and gm.user_id = auth.uid()
    )
  );

drop policy if exists guest_passes_select_own on public.game_guest_passes;
create policy guest_passes_select_own on public.game_guest_passes
  for select to authenticated
  using (created_by = auth.uid());

drop policy if exists guest_passes_delete_own on public.game_guest_passes;
create policy guest_passes_delete_own on public.game_guest_passes
  for delete to authenticated
  using (created_by = auth.uid());

-- Old passes are useless after two hours; clear them out after a day.
create or replace function public.purge_game_guest_passes()
returns void
language sql
security definer
set search_path = public
as $$
  delete from game_guest_passes where expires_at < now() - interval '1 day';
$$;
revoke all on function public.purge_game_guest_passes() from public;
