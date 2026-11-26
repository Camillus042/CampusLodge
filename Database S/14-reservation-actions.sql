-- ============================================================
-- CampusLodge database, part 14: the buttons on the reservation page
-- Paste this whole file into a NEW query in Supabase > SQL Editor > Run
--
-- Cancel a reservation, report that the owner did not show up,
-- mark the rent as paid, and show the owner's account number to the
-- student who reserved the room.
-- ============================================================

-- Two new reasons for credit
alter table public.credits drop constraint if exists credits_reason_check;
alter table public.credits add constraint credits_reason_check
  check (reason in ('did_not_like', 'expired', 'admin', 'cancelled', 'no_show'));

alter table public.reservations add column if not exists no_show boolean not null default false;

-- The owner did not show up: this credit does not count toward the 3
create or replace function public.credits_this_semester()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
  from public.credits
  where student_id = auth.uid()
    and reason <> 'no_show'
    and created_at > now() - interval '120 days';
$$;

-- Cancel: the fee becomes credit, the room reopens, counts as 1 of 3
create or replace function public.cancel_reservation(p_res uuid)
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
  perform public.give_credit(r.id, 'cancelled');
end;
$$;
revoke all on function public.cancel_reservation(uuid) from public, anon;
grant execute on function public.cancel_reservation(uuid) to authenticated;

-- The owner did not show up or refused the key: the admin decides
create or replace function public.report_no_show(p_res uuid, p_reason text, p_note text)
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
  if r.status <> 'held' then
    raise exception 'This reservation can no longer be changed.';
  end if;
  if length(trim(coalesce(p_reason, ''))) = 0 or length(trim(coalesce(p_note, ''))) = 0 then
    raise exception 'Choose what happened and write a short explanation.';
  end if;
  update public.reservations
  set status = 'disputed', no_show = true,
      claim_reasons = array[trim(p_reason)], claim_note = trim(p_note), claimed_at = now()
  where id = r.id;
end;
$$;
revoke all on function public.report_no_show(uuid, text, text) from public, anon;
grant execute on function public.report_no_show(uuid, text, text) to authenticated;

-- The student says the rent is paid
create or replace function public.mark_rent_paid(p_res uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.reservations set status = 'completed'
  where id = p_res and student_id = auth.uid() and status = 'held' and expires_at > now();
  if not found then
    raise exception 'This reservation can no longer be changed.';
  end if;
end;
$$;
revoke all on function public.mark_rent_paid(uuid) from public, anon;
grant execute on function public.mark_rent_paid(uuid) to authenticated;

-- The admin decides a disputed request
create or replace function public.admin_resolve_claim(p_res uuid, p_grant boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.reservations;
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;
  select * into r from public.reservations where id = p_res;
  if p_grant then
    perform public.give_credit(p_res, case when r.no_show then 'no_show' else 'admin' end);
  else
    update public.reservations set status = 'completed' where id = p_res;
  end if;
end;
$$;
revoke all on function public.admin_resolve_claim(uuid, boolean) from public, anon;
grant execute on function public.admin_resolve_claim(uuid, boolean) to authenticated;

-- The reservation page now also gets the owner's account number
drop function if exists public.my_reservation(uuid);
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
  badge text,
  owner_bank text,
  owner_account_number text,
  owner_account_name text
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
    end,
    p.bank_name, p.account_number, p.account_name
  from public.reservations r
  join public.listings l on l.id = r.listing_id
  join public.profiles p on p.id = l.owner_id
  where r.id = p_id and r.student_id = auth.uid() and r.status <> 'credited';
$$;
revoke all on function public.my_reservation(uuid) from public, anon;
grant execute on function public.my_reservation(uuid) to authenticated;
