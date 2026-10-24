-- Efoc — clip cards remember which way up the clip was
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- Cards already copy the path, hour and caption off the clip so they still
-- draw after retention deletes it. They now copy rotation too: without it a
-- landscape clip's thumbnail is drawn on its side once the clip row is gone,
-- which is most of a chat's history.
--
-- Backfills what can still be seen. Clips already cleaned up cannot be
-- recovered — they keep 0, exactly as they drew before this migration.

begin;

alter table public.messages
  add column if not exists card_rotation smallint not null default 0;

update public.messages m
   set card_rotation = c.rotation
  from public.clips c
 where m.clip_id = c.id
   and m.kind = 'clip'
   and c.rotation <> 0
   and m.card_rotation = 0;

do $$
declare
  gtype text;
begin
  select format_type(a.atttypid, a.atttypmod) into gtype
  from pg_attribute a
  where a.attrelid = 'public.messages'::regclass
    and a.attname = 'group_id';

  execute format($f$
    create or replace function public.post_clip_card()
    returns trigger
    language plpgsql
    security definer
    set search_path = public
    as $body$
    begin
      if tg_op = 'INSERT' then
        insert into public.messages
          (group_id, user_id, kind, clip_id,
           card_path, card_hour, card_caption, card_date, card_rotation)
        values
          (new.group_id::%1$s, new.user_id, 'clip', new.id,
           new.storage_path, new.hour_of_day, new.text_overlay, new.recorded_on,
           new.rotation)
        on conflict do nothing;
      else
        update public.messages
        set card_path = new.storage_path,
            card_caption = new.text_overlay,
            card_rotation = new.rotation
        where kind = 'clip' and clip_id = new.id;
      end if;
      return new;
    end;
    $body$;
  $f$, gtype);
end $$;

commit;
