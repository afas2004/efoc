-- Efoc — "Make a vlog" daily cap
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- Each fresh stitch costs GitHub Actions minutes, so each person gets 5 per
-- rolling 24 hours. Failed ones don't count. Making the same vlog again
-- with no new clips re-downloads the last file in the app and never
-- inserts a row. Keep the number in sync with ExportService.dailyLimit.

drop policy if exists exports_insert_own on public.exports;
create policy exports_insert_own on public.exports
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and status = 'queued'
    and storage_path is null
    and cardinality(group_ids) between 1 and 10
    and day >= current_date - 1
    and not exists (
      select 1 from unnest(group_ids) as g(id)
      where not exists (
        select 1 from public.group_members gm
        where gm.group_id::text = g.id and gm.user_id = auth.uid()
      )
    )
    and (
      select count(*) from public.exports e
      where e.user_id = auth.uid()
        and e.status <> 'failed'
        and e.created_at > now() - interval '24 hours'
    ) < 5
  );
