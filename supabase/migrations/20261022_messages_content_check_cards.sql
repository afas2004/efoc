-- Efoc — let clip and vlog chat cards past messages_content_check
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- messages_content_check (made in the dashboard, before chat cards) needs
-- every message to have text or a clip_id. Vlog cards have neither, and
-- clip cards lose clip_id when retention deletes the raw clip, so the
-- nightly stitch and cleanup both failed from 18 Oct with error 23514.
--
-- Text messages keep the old rule. Cards are checked on what they draw
-- from instead: a clip card needs its path, a vlog card its date.

alter table public.messages drop constraint if exists messages_content_check;

alter table public.messages
  add constraint messages_content_check check (
    case kind
      when 'text' then coalesce(btrim(text), '') <> '' or clip_id is not null
      when 'clip' then card_path is not null
      when 'vlog' then vlog_id is not null or card_date is not null
      else false
    end
  );
