-- Efoc — caption highlight style
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
-- 'dark' | 'light' | 'color' | 'none'. Null on older clips = 'dark'.

alter table public.clips add column if not exists text_bg text;
