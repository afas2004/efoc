-- Efoc — delete my account
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- The delete-account Edge Function removes the caller's files from Storage
-- first (Storage can't be cleaned from SQL), then calls this as the caller.
--
-- Logs they own: handed to another member if there is one, otherwise
-- deleted. Then every row with their user_id goes, then the profile and
-- the auth user. Tables or columns that don't exist are skipped, so this
-- keeps working while the schema changes.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  g record;
  heir uuid;
  t text;
begin
  if uid is null then
    raise exception 'Not signed in';
  end if;

  for g in select id from groups where owner_id = uid loop
    select user_id into heir from group_members
      where group_id = g.id and user_id <> uid
      limit 1;

    if heir is not null then
      update groups set owner_id = heir where id = g.id;
      update group_members set role = 'owner'
        where group_id = g.id and user_id = heir;
    else
      -- Nobody else is in it: the Log and anything left in it go too.
      foreach t in array array['clips', 'messages', 'vlogs', 'group_members'] loop
        if exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = t
                     and column_name = 'group_id') then
          execute format('delete from public.%I where group_id::text = $1', t)
            using g.id::text;
        end if;
      end loop;
      delete from groups where id = g.id;
    end if;
  end loop;

  -- Other people's replies to their messages stay, just unquoted.
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'messages'
               and column_name = 'reply_to_id') then
    update messages set reply_to_id = null
      where reply_to_id in (select id from messages where user_id = uid);
  end if;

  -- Children before parents (reactions before messages and clips).
  foreach t in array array[
    'message_reactions', 'reactions', 'comments', 'clip_views', 'vlog_views',
    'chat_reads', 'messages', 'clips', 'exports', 'push_tokens',
    'group_members'
  ] loop
    if exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = t
                 and column_name = 'user_id') then
      execute format('delete from public.%I where user_id = $1', t) using uid;
    end if;
  end loop;

  delete from profiles where id = uid;
  delete from auth.users where id = uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
