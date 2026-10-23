-- Efoc — undo 20261023_stickers.sql
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- This is the escape hatch, not the normal path. It deletes every sticker
-- message (text, clip and vlog messages are untouched), puts the two message
-- constraints back exactly as 20261022_messages_content_check_cards.sql and
-- 20261018_clip_chat_cards.sql left them, and drops the sticker tables and
-- bucket. Files already in the `stickers` bucket are left in place — empty the
-- bucket from the dashboard first if you want them gone.

begin;

-- ------------------------------------------------------------
-- 1. Sticker messages
-- ------------------------------------------------------------

delete from public.messages where kind = 'sticker';

alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages
  add constraint messages_kind_check
  check (kind in ('text', 'clip', 'vlog'));

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

alter table public.messages drop constraint if exists messages_sticker_id_fkey;
alter table public.messages
  drop column if exists sticker_id,
  drop column if exists sticker_url;

-- ------------------------------------------------------------
-- 2. Tables
-- ------------------------------------------------------------

drop policy if exists sticker_packs_select_member on public.sticker_packs;
drop policy if exists sticker_packs_insert_own on public.sticker_packs;
drop policy if exists sticker_packs_update_own on public.sticker_packs;
drop policy if exists sticker_packs_delete_own on public.sticker_packs;
drop policy if exists stickers_select_member on public.stickers;
drop policy if exists stickers_insert_member on public.stickers;
drop policy if exists stickers_delete_member on public.stickers;

drop table if exists public.stickers;
drop table if exists public.sticker_packs;

-- ------------------------------------------------------------
-- 3. Storage
-- ------------------------------------------------------------

drop policy if exists sticker_files_read_member on storage.objects;
drop policy if exists sticker_files_insert_member on storage.objects;
drop policy if exists sticker_files_update_member on storage.objects;
drop policy if exists sticker_files_delete_member on storage.objects;

delete from storage.buckets where id = 'stickers';

commit;
