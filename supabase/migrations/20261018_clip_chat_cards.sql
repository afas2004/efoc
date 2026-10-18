-- Efoc — clips and stitched vlogs show up in the group chat
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- Posting a clip to a Log inserts a "clip card" message in that Log's chat;
-- the stitcher saving a day's vlog inserts a "vlog card". Both are made by
-- triggers, so a card exists even if the app closes mid-send, and a clip
-- sent to several Logs gets one card in each.
--
-- Raw clips (and their thumbnails) are deleted after the day by
-- worker/stitch.py, which nulls messages.clip_id. The card keeps its own
-- copy of the path, hour and caption so it can still be drawn, and keeps
-- its reactions and replies.

-- ------------------------------------------------------------
-- 1. Card columns on messages
-- ------------------------------------------------------------

alter table public.messages
  add column if not exists kind text not null default 'text',
  add column if not exists vlog_id uuid,
  -- clip: clips.storage_path; vlog: vlogs.thumbnail_path
  add column if not exists card_path text,
  add column if not exists card_hour int,
  add column if not exists card_caption text,
  add column if not exists card_date date;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'messages_kind_check'
  ) then
    alter table public.messages
      add constraint messages_kind_check check (kind in ('text', 'clip', 'vlog'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'messages_vlog_id_fkey'
  ) then
    alter table public.messages
      add constraint messages_vlog_id_fkey foreign key (vlog_id)
      references public.vlogs (id) on delete set null;
  end if;
end $$;

-- One card per clip and per vlog.
create unique index if not exists messages_one_card_per_clip
  on public.messages (clip_id) where kind = 'clip' and clip_id is not null;
create unique index if not exists messages_one_card_per_vlog
  on public.messages (vlog_id) where kind = 'vlog' and vlog_id is not null;

-- The grid popup looks a clip's card up by clip id.
create index if not exists messages_clip_id_idx on public.messages (clip_id);

-- ------------------------------------------------------------
-- 2. Triggers
-- ------------------------------------------------------------
-- clips.group_id and vlogs.group_id are text; messages.group_id may be
-- text or uuid, so the cast is written in when the functions are made.
-- Security definer: the trigger inserts on the poster's behalf (clips) or
-- the service role's (vlogs), with no client in the loop.

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
           card_path, card_hour, card_caption, card_date)
        values
          (new.group_id::%1$s, new.user_id, 'clip', new.id,
           new.storage_path, new.hour_of_day, new.text_overlay, new.recorded_on)
        on conflict do nothing;
      else
        -- Same clip row re-uploaded: the card updates where it is.
        update public.messages
        set card_path = new.storage_path,
            card_caption = new.text_overlay
        where kind = 'clip' and clip_id = new.id;
      end if;
      return new;
    end;
    $body$;
  $f$, gtype);

  execute format($f$
    create or replace function public.post_vlog_card()
    returns trigger
    language plpgsql
    security definer
    set search_path = public
    as $body$
    declare
      poster uuid;
    begin
      if tg_op = 'INSERT' then
        -- messages.user_id is required; vlog cards are shown unattributed,
        -- so it is just the Log's owner.
        select g.owner_id into poster
        from public.groups g
        where g.id::text = new.group_id;
        if poster is null then
          return new;
        end if;

        insert into public.messages
          (group_id, user_id, kind, vlog_id, card_path, card_date)
        values
          (new.group_id::%1$s, poster, 'vlog', new.id,
           new.thumbnail_path, new.vlog_date)
        on conflict do nothing;
      else
        update public.messages
        set card_path = new.thumbnail_path
        where kind = 'vlog' and vlog_id = new.id;
      end if;
      return new;
    end;
    $body$;
  $f$, gtype);
end $$;

drop trigger if exists clips_post_chat_card on public.clips;
create trigger clips_post_chat_card
  after insert or update of storage_path, text_overlay on public.clips
  for each row execute function public.post_clip_card();

drop trigger if exists vlogs_post_chat_card on public.vlogs;
create trigger vlogs_post_chat_card
  after insert or update of thumbnail_path on public.vlogs
  for each row execute function public.post_vlog_card();

