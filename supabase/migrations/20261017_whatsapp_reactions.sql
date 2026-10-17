-- Efoc — WhatsApp-style chat reactions
--
-- Run once in the Supabase SQL Editor, after 20261017_rls_hardening.sql.
-- Safe to re-run.
--
-- One reaction per person per message. Picking the same emoji again
-- removes it; picking a different one replaces it.

-- ------------------------------------------------------------
-- 1. Shape
-- ------------------------------------------------------------

-- Newest first in the "who reacted" sheet.
alter table public.message_reactions
  add column if not exists created_at timestamptz not null default now();

-- Collapse existing duplicates (double taps, several emojis from one
-- person) down to the most recently inserted row before adding the rule.
delete from public.message_reactions a
using public.message_reactions b
where a.message_id = b.message_id
  and a.user_id = b.user_id
  and a.ctid < b.ctid;

create unique index if not exists message_reactions_one_per_user
  on public.message_reactions (message_id, user_id);

-- Swapping emoji updates the row in place.
drop policy if exists message_reactions_update_own on public.message_reactions;
create policy message_reactions_update_own on public.message_reactions
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ------------------------------------------------------------
-- 2. react_to_message(mid, e)
-- ------------------------------------------------------------
-- e = null or your current emoji -> remove
-- no reaction yet               -> add
-- different emoji               -> replace
-- Security invoker, so the insert still has to pass the membership check.

create or replace function public.react_to_message(mid uuid, e text)
returns void
language plpgsql
security invoker
as $$
declare
  cur text;
begin
  select emoji into cur
  from public.message_reactions
  where message_id = mid and user_id = auth.uid();

  if e is null or cur = e then
    delete from public.message_reactions
    where message_id = mid and user_id = auth.uid();
  elsif cur is null then
    insert into public.message_reactions (message_id, user_id, emoji)
    values (mid, auth.uid(), e);
  else
    update public.message_reactions
    set emoji = e, created_at = now()
    where message_id = mid and user_id = auth.uid();
  end if;
end;
$$;

grant execute on function public.react_to_message(uuid, text) to authenticated;
