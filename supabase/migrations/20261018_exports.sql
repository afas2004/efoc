-- Efoc — on-demand vlogs ("Make a vlog" in the ⬇ menu)
--
-- Safe to re-run. Flow: the app inserts a row here, calls the start-export
-- Edge Function, which starts .github/workflows/export.yml; worker/export.py
-- stitches the chosen Logs/hours, uploads to the exports bucket and marks
-- the row done. The app then downloads it straight to the phone.
-- Exports are deleted after a day by the nightly cleanup.

create table if not exists public.exports (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid()
               references public.profiles(id) on delete cascade,
  day          date not null,
  group_ids    text[] not null,
  hours        int[],                      -- null = every hour
  status       text not null default 'queued'
               check (status in ('queued', 'running', 'done', 'failed')),
  storage_path text,
  clip_count   int,
  error        text,
  created_at   timestamptz not null default now(),
  finished_at  timestamptz
);

create index if not exists exports_user_idx on public.exports (user_id, created_at desc);

alter table public.exports enable row level security;

drop policy if exists exports_select_own on public.exports;
create policy exports_select_own on public.exports
  for select to authenticated
  using (user_id = auth.uid());

-- Only fresh requests, only for Logs you're in, today or yesterday.
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
  );

-- ------------------------------------------------------------
-- exports bucket: private, files at {user_id}/{export_id}.mp4
-- ------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('exports', 'exports', false, 209715200, array['video/mp4'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists exports_read_own on storage.objects;
create policy exports_read_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'exports'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
