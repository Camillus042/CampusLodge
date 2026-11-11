-- ============================================================
-- CampusLodge database, part 10: a taken room stays taken
-- Paste this whole file into a NEW query in Supabase > SQL Editor > Run
-- (it is safe to run again if you ran an earlier version)
-- Change: a lister can no longer reopen a TAKEN room.
-- Only our automatic steps (credit request, ended hold) can release one.
-- ============================================================

create or replace function public.listing_rules()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Admins, the server and our own automatic steps may do anything
  if auth.uid() is null or public.is_admin()
     or current_setting('app.system', true) = '1' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.status not in ('draft', 'pending') then
      raise exception 'A new listing must start as a draft or pending.';
    end if;
    new.reject_note := null;
  else
    -- Owners can never change these
    new.owner_id := old.owner_id;
    new.reject_note := old.reject_note;
    new.created_at := old.created_at;

    -- Only these status changes are allowed for owners
    if new.status <> old.status and not (
      (old.status in ('draft', 'pending', 'rejected') and new.status in ('draft', 'pending'))
      or (old.status = 'live' and new.status = 'taken')
    ) then
      raise exception 'You cannot change the listing to that status.';
    end if;

    -- NEW: changing the details of a live listing sends it back for approval
    if old.status = 'live' and new.status = 'live' and (
      new.title, new.room_type, new.area, new.price, new.distance_min,
      new.hostel_gender, new.beds, new.amenities, new.description,
      new.whatsapp, new.call_number, new.photos
    ) is distinct from (
      old.title, old.room_type, old.area, old.price, old.distance_min,
      old.hostel_gender, old.beds, old.amenities, old.description,
      old.whatsapp, old.call_number, old.photos
    ) then
      new.status := 'pending';
    end if;
  end if;

  -- Approved hostel managers do not wait for review
  if new.status = 'pending' and public.is_approved_hostel() then
    new.status := 'live';
  end if;

  return new;
end;
$$;

create or replace function public.process_expired_holds()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.reservations;
begin
  for r in
    select * from public.reservations
    where status = 'held' and expires_at < now()
    for update skip locked
  loop
    perform set_config('app.system', '1', true);
    perform public.give_credit(r.id, 'expired');
    update public.listings set status = 'live'
    where id = r.listing_id and status = 'taken';
    perform set_config('app.system', '', true);
  end loop;
end;
$$;
revoke all on function public.process_expired_holds() from public, anon;
grant execute on function public.process_expired_holds() to authenticated;

create or replace function public.claim_credit(p_res uuid, p_reasons text[], p_note text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.reservations;
begin
  select * into r from public.reservations
  where id = p_res and student_id = auth.uid()
  for update;

  if r.id is null then
    raise exception 'Reservation not found.';
  end if;
  if r.status <> 'held' or r.expires_at < now() then
    raise exception 'This reservation can no longer be changed.';
  end if;
  if public.credits_this_semester() >= 3 then
    raise exception 'You have already used your 3 credits this semester.';
  end if;
  if coalesce(array_length(p_reasons, 1), 0) = 0 or length(trim(coalesce(p_note, ''))) = 0 then
    raise exception 'Choose a reason and write a short explanation.';
  end if;

  update public.reservations
  set status = 'claimed', claim_reasons = p_reasons, claim_note = trim(p_note), claimed_at = now()
  where id = r.id;

  -- The room is released for other students now
  perform set_config('app.system', '1', true);
  update public.listings set status = 'live'
  where id = r.listing_id and status = 'taken';
  perform set_config('app.system', '', true);
end;
$$;
revoke all on function public.claim_credit(uuid, text[], text) from public, anon;
grant execute on function public.claim_credit(uuid, text[], text) to authenticated;
