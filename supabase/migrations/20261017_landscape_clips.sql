-- Efoc — landscape clips
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- The camera screen is used with the phone turned sideways (top to the
-- left) while the app stays locked to portrait, so the file is stored as
-- the camera sees it: portrait frames with the scene lying on its side.
-- rotation = 90 means "turn 90° counter-clockwise to show it upright".
-- Older clips were recorded upright: 0.

alter table public.clips
  add column if not exists rotation smallint not null default 0;
