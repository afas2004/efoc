-- Efoc — caption position + group ownership tools
--
-- Run once in the Supabase SQL Editor. Safe to re-run.

-- ------------------------------------------------------------
-- 1. Where the caption was dragged to
-- ------------------------------------------------------------
-- Flutter Alignment: -1..1 on each axis, (0, 0) = centre.
-- Null on older clips: shown at the old default spot.

alter table public.clips
  add column if not exists text_x real,
  add column if not exists text_y real;

-- ------------------------------------------------------------
-- 2. Hand a Log over to another member
-- ------------------------------------------------------------
-- Security definer so it can update both groups.owner_id and the two
-- group_members.role rows in one go; it checks the caller itself.

create or replace function public.transfer_group_ownership(gid uuid, new_owner uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from groups
    where id = gid and owner_id = auth.uid() and not coalesce(is_personal, false)
  ) then
    raise exception 'Only the owner can hand over this Log';
  end if;

  if new_owner = auth.uid() then
    raise exception 'You already own this Log';
  end if;

  if not exists (
    select 1 from group_members where group_id = gid and user_id = new_owner
  ) then
    raise exception 'The new owner must be a member';
  end if;

  update groups set owner_id = new_owner where id = gid;
  update group_members set role = 'member'
    where group_id = gid and user_id = auth.uid();
  update group_members set role = 'owner'
    where group_id = gid and user_id = new_owner;
end;
$$;

-- ------------------------------------------------------------
-- 3. Remove someone from a Log
-- ------------------------------------------------------------
-- Their clips stay (they're part of the day); they just stop seeing the
-- Log. They can rejoin with the invite code, so rotate it if needed.

create or replace function public.remove_group_member(gid uuid, member uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from groups where id = gid and owner_id = auth.uid()
  ) then
    raise exception 'Only the owner can remove members';
  end if;

  if member = auth.uid() then
    raise exception 'Hand the Log over before leaving it';
  end if;

  delete from group_members where group_id = gid and user_id = member;
end;
$$;

revoke all on function public.transfer_group_ownership(uuid, uuid) from public;
revoke all on function public.remove_group_member(uuid, uuid) from public;
grant execute on function public.transfer_group_ownership(uuid, uuid) to authenticated;
grant execute on function public.remove_group_member(uuid, uuid) to authenticated;
