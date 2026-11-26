-- ============================================================
-- CampusLodge database, part 13: new credit rules
-- Paste this whole file into a NEW query in Supabase > SQL Editor > Run
--
-- 1. When a student asks for credit, the room is NOT released.
--    It is released only when the owner agrees (or the admin grants it).
-- 2. Once credit is given, the reservation is closed and no longer shown.
-- 3. Credit can now be used on a room from the same owner.
-- ============================================================

-- Giving credit also releases the room. This is the only place that
-- does it, so every way of getting credit behaves the same.
create or replace function public.give_credit(p_res uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.reservations;
  room_owner uuid;
begin
  select * into r from public.reservations where id = p_res;
  select owner_id into room_owner from public.listings where id = r.listing_id;
  insert into public.credits (student_id, owner_id, reservation_id, reason)
  values (r.student_id, room_owner, r.id, p_reason)
  on conflict (reservation_id) do nothing;
  update public.reservations set status = 'credited' where id = p_res;

  perform set_config('app.system', '1', true);
  update public.listings set status = 'live'
  where id = r.listing_id and status = 'taken';
  perform set_config('app.system', '', true);
end;
$$;
revoke all on function public.give_credit(uuid, text) from public, anon, authenticated;

-- The student asks for credit. The room stays taken for now.
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
end;
$$;
revoke all on function public.claim_credit(uuid, text[], text) from public, anon;
grant execute on function public.claim_credit(uuid, text[], text) to authenticated;

-- A student no longer sees a reservation that has become credit
create or replace function public.my_reservation(p_id uuid)
returns table (
  id uuid,
  reference text,
  status text,
  created_at timestamptz,
  expires_at timestamptz,
  room_title text,
  room_area text,
  room_photo text,
  owner_name text,
  price integer,
  room_type text,
  distance_min integer,
  whatsapp text,
  call_number text,
  badge text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id, r.reference, r.status, r.created_at, r.expires_at,
    r.room_title, r.room_area, r.room_photo, r.owner_name,
    l.price, l.room_type, l.distance_min, l.whatsapp, l.call_number,
    case
      when p.role = 'hostel' and p.approved then 'verified'
      when p.role in ('landlord', 'agent') and p.trusted then 'trusted'
      else null
    end
  from public.reservations r
  join public.listings l on l.id = r.listing_id
  join public.profiles p on p.id = l.owner_id
  where r.id = p_id and r.student_id = auth.uid() and r.status <> 'credited';
$$;
revoke all on function public.my_reservation(uuid) from public, anon;
grant execute on function public.my_reservation(uuid) to authenticated;

-- Credit works on any room, including from the same owner
create or replace function public.reserve_room(p_listing uuid, p_use_credit boolean default false)
returns public.reservations
language plpgsql
security definer
set search_path = public
as $$
declare
  me public.profiles;
  room public.listings;
  owner_label text;
  credit_id uuid;
  result public.reservations;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null or me.role <> 'student' then
    raise exception 'Only students can reserve a room.';
  end if;
  if me.status <> 'active' then
    raise exception 'Your account cannot reserve rooms right now.';
  end if;

  perform public.process_expired_holds();

  if exists (
    select 1 from public.reservations
    where student_id = me.id and status = 'held' and expires_at > now()
  ) then
    raise exception 'You already have an active reservation.';
  end if;

  select * into room from public.listings
  where id = p_listing and status = 'live'
  for update;
  if room.id is null then
    raise exception 'This room is no longer available.';
  end if;

  if p_use_credit then
    if me.credit_frozen then
      raise exception 'Your credit is frozen right now.';
    end if;
    select id into credit_id from public.credits
    where student_id = me.id and status = 'available'
    order by created_at
    limit 1
    for update;
    if credit_id is null then
      raise exception 'You have no credit to use.';
    end if;
  end if;

  select coalesce(nullif(p.hostel_name, ''), p.full_name) into owner_label
  from public.profiles p where p.id = room.owner_id;

  insert into public.reservations (
    student_id, listing_id, reference, room_title, room_area, room_photo, owner_name, paid_with
  ) values (
    me.id, room.id,
    'CL-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8)),
    room.title, room.area, room.photos[1], owner_label,
    case when p_use_credit then 'credit' else 'demo' end
  )
  returning * into result;

  if p_use_credit then
    update public.credits
    set status = 'used', used_reservation_id = result.id
    where id = credit_id;
  end if;

  update public.listings set status = 'taken' where id = room.id;
  return result;
end;
$$;
revoke all on function public.reserve_room(uuid, boolean) from public, anon;
grant execute on function public.reserve_room(uuid, boolean) to authenticated;
