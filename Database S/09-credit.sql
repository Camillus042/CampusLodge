-- ============================================================
-- CampusLodge database, part 9: credit
-- Paste this whole file into a NEW query in Supabase > SQL Editor > Run
--
-- Rules built here:
--  * "There is a problem" -> the student asks for credit, the room reopens,
--    the owner confirms (or disputes, then the admin decides)
--  * If the 48-hour hold ends with no action, the fee becomes credit anyway
--  * Max 3 credits per student in a semester (counted as the last 120 days)
--  * Credit can be used by ticking "Use my credit" when reserving,
--    but not on a room from the same owner, and not while credit is frozen
-- ============================================================

alter table public.profiles
  add column if not exists credit_frozen boolean not null default false;

-- New things a reservation can remember
alter table public.reservations
  add column if not exists paid_with text not null default 'demo',
  add column if not exists claim_reasons text[],
  add column if not exists claim_note text,
  add column if not exists claimed_at timestamptz;

alter table public.reservations drop constraint if exists reservations_status_check;
alter table public.reservations add constraint reservations_status_check
  check (status in ('held', 'claimed', 'disputed', 'credited', 'completed', 'cancelled'));

-- ------------------------------------------------------------
-- The credits
-- ------------------------------------------------------------
create table public.credits (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  reservation_id uuid not null unique references public.reservations(id) on delete cascade,
  amount integer not null default 5000,
  reason text not null check (reason in ('did_not_like', 'expired', 'admin')),
  status text not null default 'available' check (status in ('available', 'used')),
  used_reservation_id uuid references public.reservations(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.credits enable row level security;

create policy "student reads own credits"
  on public.credits for select
  to authenticated
  using (student_id = auth.uid() or public.is_admin());

grant select on public.credits to authenticated;

-- A small helper: give the student a credit for a reservation
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
end;
$$;
revoke all on function public.give_credit(uuid, text) from public, anon, authenticated;

-- ------------------------------------------------------------
-- Holds that ended: the fee becomes credit, the room reopens.
-- The site calls this when someone opens a page.
-- ------------------------------------------------------------
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
    perform public.give_credit(r.id, 'expired');
    update public.listings set status = 'live'
    where id = r.listing_id and status = 'taken';
  end loop;
end;
$$;
revoke all on function public.process_expired_holds() from public, anon;
grant execute on function public.process_expired_holds() to authenticated;

-- ------------------------------------------------------------
-- How much credit does the student have, and how many used this semester
-- ------------------------------------------------------------
create or replace function public.my_credit_balance()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(amount), 0)::integer
  from public.credits
  where student_id = auth.uid() and status = 'available';
$$;

create or replace function public.credits_this_semester()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
  from public.credits
  where student_id = auth.uid() and created_at > now() - interval '120 days';
$$;

revoke all on function public.my_credit_balance() from public, anon;
revoke all on function public.credits_this_semester() from public, anon;
grant execute on function public.my_credit_balance() to authenticated;
grant execute on function public.credits_this_semester() to authenticated;

-- ------------------------------------------------------------
-- The student says "There is a problem" and asks for credit
-- ------------------------------------------------------------
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
  update public.listings set status = 'live'
  where id = r.listing_id and status = 'taken';
end;
$$;
revoke all on function public.claim_credit(uuid, text[], text) from public, anon;
grant execute on function public.claim_credit(uuid, text[], text) to authenticated;

-- ------------------------------------------------------------
-- The owner sees the requests for their rooms and answers them
-- ------------------------------------------------------------
create or replace function public.owner_claims()
returns table (
  id uuid,
  room_title text,
  student_name text,
  claim_reasons text[],
  claim_note text,
  claimed_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.room_title, split_part(p.full_name, ' ', 1),
         r.claim_reasons, r.claim_note, r.claimed_at
  from public.reservations r
  join public.listings l on l.id = r.listing_id
  join public.profiles p on p.id = r.student_id
  where l.owner_id = auth.uid() and r.status = 'claimed'
  order by r.claimed_at;
$$;
revoke all on function public.owner_claims() from public, anon;
grant execute on function public.owner_claims() to authenticated;

-- confirm = true: "the student did not take the room" -> credit
-- confirm = false: "the student took it" -> goes to the admin
create or replace function public.owner_answer_claim(p_res uuid, p_confirm boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.reservations;
begin
  select r2.* into r
  from public.reservations r2
  join public.listings l on l.id = r2.listing_id
  where r2.id = p_res and l.owner_id = auth.uid() and r2.status = 'claimed'
  for update of r2;

  if r.id is null then
    raise exception 'Request not found.';
  end if;

  if p_confirm then
    perform public.give_credit(r.id, 'did_not_like');
  else
    update public.reservations set status = 'disputed' where id = r.id;
  end if;
end;
$$;
revoke all on function public.owner_answer_claim(uuid, boolean) from public, anon;
grant execute on function public.owner_answer_claim(uuid, boolean) to authenticated;

-- The admin decides a disputed request
create or replace function public.admin_resolve_claim(p_res uuid, p_grant boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;
  if p_grant then
    perform public.give_credit(p_res, 'admin');
  else
    update public.reservations set status = 'completed' where id = p_res;
  end if;
end;
$$;
revoke all on function public.admin_resolve_claim(uuid, boolean) from public, anon;
grant execute on function public.admin_resolve_claim(uuid, boolean) to authenticated;

-- ------------------------------------------------------------
-- Reserve a room: now also with credit
-- ------------------------------------------------------------
drop function if exists public.reserve_room(uuid);

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
    where student_id = me.id and status = 'available' and owner_id <> room.owner_id
    order by created_at
    limit 1
    for update;
    if credit_id is null then
      raise exception 'You have no credit that can be used on this room. Credit cannot be used on a room from the same owner.';
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
