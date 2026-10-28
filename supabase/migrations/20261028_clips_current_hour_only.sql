-- Efoc — clips can only be sent for the current hour
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- The app only opens the camera for the current hour, but nothing stopped an
-- old build or a crafted request from upserting a clip into a past (or
-- future) hour. This trigger rejects any insert or update from a signed-in
-- user unless the row's slot (recorded_on + hour_of_day, Asia/Kuala_Lumpur)
-- is open now: from 1 minute before the hour (phone clock drift) until
-- 5 minutes after it ends (ClipService.hourGrace — a take started at 3:59
-- can still be sent at 4:03).
--
-- Not affected: the service role (stitch / archive / export workers), the
-- SQL Editor (postgres), deletes, and existing rows — nothing is rewritten.

begin;

create or replace function public.clips_hour_open()
returns trigger
language plpgsql
as $$
declare
  local_now timestamp := now() at time zone 'Asia/Kuala_Lumpur';
  slot_start timestamp :=
    new.recorded_on::timestamp + make_interval(hours => new.hour_of_day);
begin
  if coalesce(auth.role(), '') = 'service_role'
     or current_user in ('postgres', 'supabase_admin', 'service_role') then
    return new;
  end if;

  if local_now < slot_start - interval '1 minute'
     or local_now >= slot_start + interval '1 hour 5 minutes' then
    raise exception 'That hour has closed'
      using errcode = 'check_violation',
            hint = 'Clips can only be sent for the current hour.';
  end if;

  return new;
end;
$$;

drop trigger if exists clips_hour_open on public.clips;
create trigger clips_hour_open
  before insert or update on public.clips
  for each row execute function public.clips_hour_open();

commit;
