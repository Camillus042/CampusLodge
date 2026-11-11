-- ============================================================
-- CampusLodge database, part 8: the reservation page
-- Paste this whole file into a NEW query in Supabase > SQL Editor > Run
-- Gives a student the details of ONE of their own reservations,
-- even after the room is marked as taken.
-- ============================================================

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
  where r.id = p_id and r.student_id = auth.uid();
$$;

revoke all on function public.my_reservation(uuid) from public, anon;
grant execute on function public.my_reservation(uuid) to authenticated;
