-- Efoc — save a single sticker, and the "Saved" pack that holds them
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- Two ways in without a file:
--   * long-press a sticker in a chat  -> save_sticker(url)
--   * share an image to efoc from another app -> upload, then save_sticker(url)
--
-- Both land in a pack called "Saved" that is created on first use. The bytes
-- are not copied: the new row points at the same public URL, so saving a
-- sticker costs one row.

begin;

-- The pack the saves land in. Creates it the first time, then reuses it.
create or replace function public.ensure_saved_pack()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  v_pack uuid;
  v_slug text;
  v_try int := 1;
begin
  if uid is null then
    raise exception 'not signed in';
  end if;

  select id into v_pack
    from public.sticker_packs
   where owner_id = uid
     and name = 'Saved'
   order by created_at
   limit 1;

  if v_pack is not null then
    return v_pack;
  end if;

  loop
    v_slug := case when v_try = 1 then 'saved' else 'saved-' || v_try end;
    exit when not exists (
      select 1 from public.sticker_packs where slug = v_slug
    );
    v_try := v_try + 1;
    if v_try > 50 then
      -- Someone owns every 'saved-N' slug; fall back to something unique.
      v_slug := 'saved-' || substr(replace(uid::text, '-', ''), 1, 8);
      exit;
    end if;
  end loop;

  insert into public.sticker_packs (owner_id, slug, name)
  values (uid, v_slug, 'Saved')
  returning id into v_pack;

  return v_pack;
end;
$$;

-- Appends a sticker to "Saved", ignoring one that is already there, and makes
-- sure the pack is in the tray (un-archiving it if it had been put away).
create or replace function public.save_sticker(
  p_url text,
  p_emojis text[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  v_pack uuid;
  v_pos int;
begin
  if uid is null then
    raise exception 'not signed in';
  end if;
  if p_url is null or btrim(p_url) = '' then
    raise exception 'no sticker';
  end if;

  v_pack := public.ensure_saved_pack();

  if not exists (
    select 1 from public.stickers
     where pack_id = v_pack and url = p_url
  ) then
    select coalesce(max(position) + 1, 0)
      into v_pos
      from public.stickers
     where pack_id = v_pack;

    insert into public.stickers (pack_id, url, emojis, position)
    values (v_pack, p_url, coalesce(p_emojis, '{}'), v_pos);
  end if;

  -- Reinstalls (and bumps to the front) so a saved sticker is never invisible.
  perform public.install_sticker_pack(v_pack);

  return v_pack;
end;
$$;

grant execute on function public.ensure_saved_pack() to authenticated;
grant execute on function public.save_sticker(text, text[]) to authenticated;

commit;
