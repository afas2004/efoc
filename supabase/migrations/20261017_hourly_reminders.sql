-- Efoc — hourly reminders (push notifications)
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- The sender (worker/remind.py, run hourly by .github/workflows/remind.yml)
-- uses the service role key, so it bypasses RLS.

-- ------------------------------------------------------------
-- 1. Preference
-- ------------------------------------------------------------
-- Off until the user turns it on and the browser grants permission.

alter table public.profiles
  add column if not exists reminders_enabled boolean not null default false;

-- ------------------------------------------------------------
-- 2. push_tokens: one row per device/browser
-- ------------------------------------------------------------
-- profiles.fcm_token only holds one device; a phone and a laptop each
-- need their own token.

create table if not exists public.push_tokens (
  token      text primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  platform   text not null default 'web',
  updated_at timestamptz not null default now()
);

create index if not exists push_tokens_user_idx on public.push_tokens (user_id);

alter table public.push_tokens enable row level security;

drop policy if exists push_tokens_select_own on public.push_tokens;
create policy push_tokens_select_own on public.push_tokens
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists push_tokens_insert_own on public.push_tokens;
create policy push_tokens_insert_own on public.push_tokens
  for insert to authenticated
  with check (user_id = auth.uid());

-- A browser that signs into another account re-registers the same token
-- under the new user, so the old owner's row has to be replaceable.
drop policy if exists push_tokens_update_own on public.push_tokens;
create policy push_tokens_update_own on public.push_tokens
  for update to authenticated
  using (true)
  with check (user_id = auth.uid());

drop policy if exists push_tokens_delete_own on public.push_tokens;
create policy push_tokens_delete_own on public.push_tokens
  for delete to authenticated
  using (user_id = auth.uid());
