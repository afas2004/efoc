-- Efoc — free-tier retention
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- Policy: Supabase only keeps today's raw clips and yesterday's stitched
-- vlog. The stitcher (worker/stitch.py) deletes the rest; stitched vlogs
-- are deleted only once your laptop has backed them up
-- (worker/backup.py sets vlogs.backed_up_at), or after 7 days regardless.

-- ------------------------------------------------------------
-- 1. Backup marker
-- ------------------------------------------------------------

alter table public.vlogs
  add column if not exists backed_up_at timestamptz;

-- ------------------------------------------------------------
-- 2. Let clip rows be deleted
-- ------------------------------------------------------------
-- Anything pointing at a clip goes with it (comments, reactions, views),
-- except chat messages: those keep their text and just lose the clip.
-- Foreign key names aren't in the schema snapshot, so find them.

do $$
declare
  fk record;
  cols text;
  ref_cols text;
  action text;
begin
  for fk in
    select c.oid, c.conname, c.conrelid::regclass as tbl, c.conkey, c.confkey,
           c.confdeltype
    from pg_constraint c
    where c.contype = 'f'
      and c.confrelid = 'public.clips'::regclass
  loop
    action := case
      when fk.tbl = 'public.messages'::regclass then 'set null'
      else 'cascade'
    end;

    -- Already right: 'c' = cascade, 'n' = set null.
    continue when (action = 'cascade' and fk.confdeltype = 'c')
               or (action = 'set null' and fk.confdeltype = 'n');

    select string_agg(quote_ident(a.attname), ', ' order by k.ord)
      into cols
    from unnest(fk.conkey) with ordinality k(attnum, ord)
    join pg_attribute a on a.attrelid = fk.tbl and a.attnum = k.attnum;

    select string_agg(quote_ident(a.attname), ', ' order by k.ord)
      into ref_cols
    from unnest(fk.confkey) with ordinality k(attnum, ord)
    join pg_attribute a
      on a.attrelid = 'public.clips'::regclass and a.attnum = k.attnum;

    execute format('alter table %s drop constraint %I', fk.tbl, fk.conname);
    execute format(
      'alter table %s add constraint %I foreign key (%s) '
      'references public.clips (%s) on delete %s',
      fk.tbl, fk.conname, cols, ref_cols, action
    );
    raise notice '% -> on delete %', fk.conname, action;
  end loop;
end $$;
