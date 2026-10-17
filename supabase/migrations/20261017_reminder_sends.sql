-- Efoc — one reminder per hour
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- Reminders can be started by both GitHub's own schedule and an external
-- timer (cron-job.org). worker/remind.py claims the hour here first, so
-- whichever arrives second sends nothing. Service role only: no policies,
-- so app users can't read or write it.

create table if not exists public.reminder_sends (
  hour_key text primary key,          -- e.g. '2026-10-17T14'
  sent_at  timestamptz not null default now()
);

alter table public.reminder_sends enable row level security;
