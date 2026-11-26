-- ============================================================
-- CampusLodge: the whole database in ONE file
--
-- HOW TO USE
--   1. Make a new, empty Supabase project.
--   2. Supabase > SQL Editor > New query.
--   3. Paste this whole file and click Run.
--   4. Sign up on the site with your own email.
--   5. Run the small query in PART 13 to make yourself admin.
--
-- Do NOT run this on a project that already has the tables.
--
-- WHAT IS INSIDE
--   Part 1. Tables
--   Part 2. Who is who: admin and listing helpers
--   Part 3. Row-level security (who can read and change what)
--   Part 4. Photo storage
--   Part 5. Sign-up
--   Part 6. Listings
--   Part 7. Reservations and credit
--   Part 8. Reports
--   Part 9. Admin tools
--   Part 10. Profile, contact and appeals
--   Part 11. Notifications
--   Part 12. Permissions
--   Part 13. Make yourself admin
-- ============================================================


-- ============================================================
-- PART 1: Tables
-- Every table the site uses, with its rules (checks) and links (keys).
-- ============================================================

-- Everyone who signs up: students, landlords, agents, hostel managers and admins.
create table public.profiles (
  id             uuid not null,
  role           text default 'student' not null,
  full_name      text default '' not null,
  phone          text,
  hostel_name    text,
  hostel_gender  text,
  approved       boolean default false not null,
  status         text default 'active' not null,
  created_at     timestamptz default now() not null,
  agreed_at      timestamptz,
  trusted        boolean default false not null,
  credit_frozen  boolean default false not null,
  warnings       integer default 0 not null,
  matric         text,
  bank_name      text,
  account_number text,
  account_name   text,
  notify_rooms   boolean default true not null,
  notify_tips    boolean default false not null,
  constraint profiles_pkey primary key (id),
  constraint profiles_id_fkey foreign key (id) references auth.users(id) on delete cascade,
  constraint profiles_role_check check ((role in ('student', 'landlord', 'agent', 'hostel', 'admin'))),
  constraint profiles_status_check check ((status in ('active', 'banned')))
);

-- Rooms listed by landlords, agents and hostel managers.
create table public.listings (
  id            uuid default gen_random_uuid() not null,
  owner_id      uuid default auth.uid() not null,
  kind          text not null,
  title         text not null,
  room_type     text,
  area          text,
  price         integer not null,
  distance_min  integer,
  hostel_gender text,
  beds          integer,
  amenities     text[] default '{}' not null,
  description   text,
  whatsapp      text,
  call_number   text,
  photos        text[] default '{}' not null,
  status        text default 'draft' not null,
  reject_note   text,
  created_at    timestamptz default now() not null,
  constraint listings_pkey primary key (id),
  constraint listings_owner_id_fkey foreign key (owner_id) REFERENCES profiles(id) on delete cascade,
  constraint listings_beds_check check ((beds >= 0)),
  constraint listings_description_check check ((char_length(description) <= 2000)),
  constraint listings_distance_min_check check ((distance_min >= 0)),
  constraint listings_hostel_gender_check check ((hostel_gender in ('male', 'female', 'mixed'))),
  constraint listings_kind_check check ((kind in ('apartment', 'hostel'))),
  constraint listings_photos_check check ((cardinality(photos) <= 5)),
  constraint listings_price_check check ((price > 0)),
  constraint listings_status_check check ((status in ('draft', 'pending', 'live', 'rejected', 'taken'))),
  constraint listings_title_check check (((char_length(title) >= 3) AND (char_length(title) <= 100)))
);

-- A student's 48-hour hold on a room (the 5,000 naira booking fee).
create table public.reservations (
  id            uuid default gen_random_uuid() not null,
  student_id    uuid not null,
  listing_id    uuid not null,
  reference     text not null,
  amount        integer default 5000 not null,
  status        text default 'held' not null,
  room_title    text not null,
  room_area     text,
  room_photo    text,
  owner_name    text,
  created_at    timestamptz default now() not null,
  expires_at    timestamptz default now() + interval '48 hours' not null,
  paid_with     text default 'demo' not null,
  claim_reasons text[],
  claim_note    text,
  claimed_at    timestamptz,
  no_show       boolean default false not null,
  constraint reservations_pkey primary key (id),
  constraint reservations_reference_key unique (reference),
  constraint reservations_listing_id_fkey foreign key (listing_id) REFERENCES listings(id) on delete cascade,
  constraint reservations_student_id_fkey foreign key (student_id) REFERENCES profiles(id) on delete cascade,
  constraint reservations_status_check check ((status in ('held', 'claimed', 'disputed', 'credited', 'completed', 'cancelled')))
);

-- Booking-fee credit a student can use on another room.
create table public.credits (
  id                  uuid default gen_random_uuid() not null,
  student_id          uuid not null,
  owner_id            uuid not null,
  reservation_id      uuid not null,
  amount              integer default 5000 not null,
  reason              text not null,
  status              text default 'available' not null,
  used_reservation_id uuid,
  created_at          timestamptz default now() not null,
  constraint credits_pkey primary key (id),
  constraint credits_reservation_id_key unique (reservation_id),
  constraint credits_owner_id_fkey foreign key (owner_id) REFERENCES profiles(id) on delete cascade,
  constraint credits_reservation_id_fkey foreign key (reservation_id) REFERENCES reservations(id) on delete cascade,
  constraint credits_student_id_fkey foreign key (student_id) REFERENCES profiles(id) on delete cascade,
  constraint credits_used_reservation_id_fkey foreign key (used_reservation_id) REFERENCES reservations(id) on delete set null,
  constraint credits_reason_check check ((reason in ('did_not_like', 'expired', 'admin', 'cancelled', 'no_show'))),
  constraint credits_status_check check ((status in ('available', 'used')))
);

-- Students reporting a listing.
create table public.reports (
  id          uuid default gen_random_uuid() not null,
  listing_id  uuid not null,
  reporter_id uuid not null,
  reason      text not null,
  details     text,
  status      text default 'open' not null,
  created_at  timestamptz default now() not null,
  constraint reports_pkey primary key (id),
  constraint reports_listing_id_fkey foreign key (listing_id) REFERENCES listings(id) on delete cascade,
  constraint reports_reporter_id_fkey foreign key (reporter_id) REFERENCES profiles(id) on delete cascade,
  constraint reports_reason_check check ((reason in ('fake', 'wrong', 'outside', 'taken', 'other'))),
  constraint reports_status_check check ((status in ('open', 'dismissed', 'actioned')))
);

-- What admins did to users (only admins can read it).
create table public.admin_log (
  id         uuid default gen_random_uuid() not null,
  admin_id   uuid,
  user_id    uuid,
  action     text not null,
  note       text,
  created_at timestamptz default now() not null,
  constraint admin_log_pkey primary key (id),
  constraint admin_log_admin_id_fkey foreign key (admin_id) REFERENCES profiles(id) on delete set null,
  constraint admin_log_user_id_fkey foreign key (user_id) REFERENCES profiles(id) on delete cascade
);

-- Contact messages and ban appeals, answered in the admin dashboard.
create table public.inbox (
  id         uuid default gen_random_uuid() not null,
  kind       text not null,
  user_id    uuid,
  name       text,
  email      text,
  body       text not null,
  status     text default 'new' not null,
  created_at timestamptz default now() not null,
  constraint inbox_pkey primary key (id),
  constraint inbox_user_id_fkey foreign key (user_id) REFERENCES profiles(id) on delete cascade,
  constraint inbox_body_check check (((char_length(body) >= 2) AND (char_length(body) <= 2000))),
  constraint inbox_kind_check check ((kind in ('contact', 'appeal'))),
  constraint inbox_status_check check ((status in ('new', 'done', 'restored', 'rejected')))
);

-- The messages shown on each person's Notifications page.
create table public.notifications (
  id         uuid default gen_random_uuid() not null,
  user_id    uuid not null,
  icon       text default 'info' not null,
  title      text not null,
  body       text,
  link       text,
  is_read    boolean default false not null,
  created_at timestamptz default now() not null,
  constraint notifications_pkey primary key (id),
  constraint notifications_user_id_fkey foreign key (user_id) REFERENCES profiles(id) on delete cascade
);

create index notifications_user_idx on public.notifications using btree (user_id, created_at desc);


-- ============================================================
-- PART 2: Who is who: admin and listing helpers
-- Small yes/no questions that the rules below ask.
-- ============================================================

create or replace function public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and status = 'active'
  );
$function$;

create or replace function public.can_list()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('landlord', 'agent', 'hostel')
      and status = 'active'
  );
$function$;

create or replace function public.is_approved_hostel()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'hostel' and approved and status = 'active'
  );
$function$;


-- ============================================================
-- PART 3: Row-level security
-- Switches on protection for every table, then says who may read or change rows.
-- The website can only do what these rules allow.
-- ============================================================

alter table public.profiles enable row level security;
alter table public.listings enable row level security;
alter table public.reservations enable row level security;
alter table public.credits enable row level security;
alter table public.reports enable row level security;
alter table public.admin_log enable row level security;
alter table public.inbox enable row level security;
alter table public.notifications enable row level security;

-- ------------------------------------------------------------
-- Table: profiles
-- ------------------------------------------------------------
create policy "admin reads profiles"
  on public.profiles for select
  to authenticated
  using (is_admin());

create policy "read own profile"
  on public.profiles for select
  to authenticated
  using ((id = auth.uid()));

-- ------------------------------------------------------------
-- Table: listings
-- ------------------------------------------------------------
create policy "admin edits listings"
  on public.listings for update
  to authenticated
  using (is_admin())
  with check (is_admin());

create policy "admin sees all listings"
  on public.listings for select
  to authenticated
  using (is_admin());

create policy "everyone logged in sees live listings"
  on public.listings for select
  to authenticated
  using ((status = 'live'::text));

create policy "listers add listings"
  on public.listings for insert
  to authenticated
  with check (((owner_id = auth.uid()) AND can_list() AND ((status = ANY (ARRAY['draft'::text, 'pending'::text])) OR ((status = 'live'::text) AND is_approved_hostel()))));

create policy "owner deletes own listing"
  on public.listings for delete
  to authenticated
  using ((owner_id = auth.uid()));

create policy "owner edits own listing"
  on public.listings for update
  to authenticated
  using (((owner_id = auth.uid()) AND can_list()))
  with check (((owner_id = auth.uid()) AND ((status = ANY (ARRAY['draft'::text, 'pending'::text, 'taken'::text])) OR (status = 'live'::text))));

create policy "owner sees own listings"
  on public.listings for select
  to authenticated
  using ((owner_id = auth.uid()));

-- ------------------------------------------------------------
-- Table: reservations
-- ------------------------------------------------------------
create policy "owner reads reservations of own rooms"
  on public.reservations for select
  to authenticated
  using ((EXISTS ( SELECT 1
   FROM listings l
  WHERE ((l.id = reservations.listing_id) AND (l.owner_id = auth.uid())))));

create policy "student reads own reservations"
  on public.reservations for select
  to authenticated
  using (((student_id = auth.uid()) OR is_admin()));

-- ------------------------------------------------------------
-- Table: credits
-- ------------------------------------------------------------
create policy "student reads own credits"
  on public.credits for select
  to authenticated
  using (((student_id = auth.uid()) OR is_admin()));

-- ------------------------------------------------------------
-- Table: reports
-- ------------------------------------------------------------
create policy "admin reads reports"
  on public.reports for select
  to authenticated
  using (is_admin());

-- ------------------------------------------------------------
-- Table: admin_log
-- ------------------------------------------------------------
create policy "admin reads log"
  on public.admin_log for select
  to authenticated
  using (is_admin());

-- ------------------------------------------------------------
-- Table: inbox
-- ------------------------------------------------------------
create policy "admin reads inbox"
  on public.inbox for select
  to authenticated
  using (is_admin());

-- ------------------------------------------------------------
-- Table: notifications
-- ------------------------------------------------------------
create policy "read own notifications"
  on public.notifications for select
  to authenticated
  using ((user_id = auth.uid()));

-- Nobody changes a profile straight from the website.
-- Changes go through the safe functions in the parts below.
revoke insert, update, delete on public.profiles from anon, authenticated;
revoke all on public.profiles from anon;


-- ============================================================
-- PART 4: Photo storage
-- ============================================================

-- Room photos: a public folder, 5 MB each, pictures only.
-- Each lister can only add files inside their own folder.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'listing-photos',
  'listing-photos',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
);

create policy "listers add photos to own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.can_list()
  );

create policy "listers delete own photos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'listing-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );


-- ============================================================
-- PART 5: Sign-up
-- When someone signs up, a profile is created for them automatically.
-- It refuses anyone who did not agree to the Terms.
-- ============================================================

create or replace function public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  chosen text := coalesce(new.raw_user_meta_data ->> 'role', 'student');
begin
  if coalesce(new.raw_user_meta_data ->> 'agreed', '') <> 'true' then
    raise exception 'You must agree to the Terms and the Fair Use Agreement.';
  end if;

  if chosen not in ('student', 'landlord', 'agent', 'hostel') then
    chosen := 'student';
  end if;

  insert into public.profiles (
    id, role, full_name, phone, hostel_name, hostel_gender, approved, agreed_at
  )
  values (
    new.id,
    chosen,
    left(coalesce(new.raw_user_meta_data ->> 'full_name', ''), 100),
    nullif(left(trim(coalesce(new.raw_user_meta_data ->> 'phone', '')), 20), ''),
    nullif(left(trim(coalesce(new.raw_user_meta_data ->> 'hostel_name', '')), 100), ''),
    nullif(left(trim(coalesce(new.raw_user_meta_data ->> 'hostel_gender', '')), 30), ''),
    chosen = 'student',
    now()
  );

  return new;
end;
$function$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();



-- ============================================================
-- PART 6: Listings
-- The rules for listing statuses, and what students can see.
-- ============================================================

-- ------------------------------------------------------------
-- Status rules (draft > pending > live > taken)
-- ------------------------------------------------------------
create or replace function public.listing_rules()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create trigger listing_rules_trigger
  before insert or update on public.listings
  for each row execute function listing_rules();

-- ------------------------------------------------------------
-- What students see
-- ------------------------------------------------------------
create or replace function public.live_rooms()
 RETURNS TABLE(id uuid, kind text, title text, room_type text, area text, price integer, distance_min integer, hostel_gender text, beds integer, amenities text[], description text, whatsapp text, call_number text, photos text[], created_at timestamp with time zone, owner_name text, owner_role text, badge text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    l.id, l.kind, l.title, l.room_type, l.area, l.price, l.distance_min,
    l.hostel_gender, l.beds, l.amenities, l.description, l.whatsapp,
    l.call_number, l.photos, l.created_at,
    coalesce(nullif(p.hostel_name, ''), p.full_name),
    p.role,
    case
      when p.role = 'hostel' and p.approved then 'verified'
      when p.role in ('landlord', 'agent') and p.trusted then 'trusted'
      else null
    end
  from public.listings l
  join public.profiles p on p.id = l.owner_id
  where l.status = 'live' and p.status = 'active';
$function$;

create or replace function public.owner_info(listing uuid)
 RETURNS TABLE(display_name text, role text, approved boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(nullif(p.hostel_name, ''), p.full_name), p.role, p.approved
  from public.listings l
  join public.profiles p on p.id = l.owner_id
  where l.id = listing and l.status in ('live', 'taken');
$function$;


-- ============================================================
-- PART 7: Reservations and credit
-- Hold a room, ask for credit, cancel, and the 3-credits-per-semester limit.
-- ============================================================

-- ------------------------------------------------------------
-- Credit helpers
-- ------------------------------------------------------------
create or replace function public.give_credit(p_res uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.my_credit_balance()
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(sum(amount), 0)::integer
  from public.credits
  where student_id = auth.uid() and status = 'available';
$function$;

create or replace function public.credits_this_semester()
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select count(*)::integer
  from public.credits
  where student_id = auth.uid()
    and reason <> 'no_show'
    and created_at > now() - interval '120 days';
$function$;
-- ------------------------------------------------------------
-- Reserve a room
-- ------------------------------------------------------------
create or replace function public.process_expired_holds()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.reserve_room(p_listing uuid, p_use_credit boolean DEFAULT false)
 RETURNS reservations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.my_reservation(p_id uuid)
 RETURNS TABLE(id uuid, reference text, status text, created_at timestamp with time zone, expires_at timestamp with time zone, room_title text, room_area text, room_photo text, owner_name text, price integer, room_type text, distance_min integer, whatsapp text, call_number text, badge text, owner_bank text, owner_account_number text, owner_account_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
-- ------------------------------------------------------------
-- What the student can do
-- ------------------------------------------------------------
create or replace function public.claim_credit(p_res uuid, p_reasons text[], p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.cancel_reservation(p_res uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.report_no_show(p_res uuid, p_reason text, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.mark_rent_paid(p_res uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.reservations set status = 'completed'
  where id = p_res and student_id = auth.uid() and status = 'held' and expires_at > now();
  if not found then
    raise exception 'This reservation can no longer be changed.';
  end if;
end;
$function$;
-- ------------------------------------------------------------
-- What the owner and the admin can do
-- ------------------------------------------------------------
create or replace function public.owner_claims()
 RETURNS TABLE(id uuid, room_title text, student_name text, claim_reasons text[], claim_note text, claimed_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select r.id, r.room_title, split_part(p.full_name, ' ', 1),
         r.claim_reasons, r.claim_note, r.claimed_at
  from public.reservations r
  join public.listings l on l.id = r.listing_id
  join public.profiles p on p.id = r.student_id
  where l.owner_id = auth.uid() and r.status = 'claimed'
  order by r.claimed_at;
$function$;

create or replace function public.owner_answer_claim(p_res uuid, p_confirm boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

create or replace function public.admin_resolve_claim(p_res uuid, p_grant boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;


-- ============================================================
-- PART 8: Reports
-- Students report a listing; the admin looks at it.
-- ============================================================

create or replace function public.report_listing(p_listing uuid, p_reason text, p_details text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Please log in first.';
  end if;
  if not exists (select 1 from public.listings where id = p_listing and status = 'live') then
    raise exception 'This listing is no longer live.';
  end if;
  if exists (
    select 1 from public.reports
    where listing_id = p_listing and reporter_id = auth.uid() and status = 'open'
  ) then
    raise exception 'You have already reported this listing.';
  end if;
  insert into public.reports (listing_id, reporter_id, reason, details)
  values (p_listing, auth.uid(), p_reason, left(coalesce(p_details, ''), 500));
end;
$function$;

create or replace function public.admin_reports()
 RETURNS TABLE(id uuid, listing_id uuid, listing_title text, owner_name text, reason text, details text, created_at timestamp with time zone, report_count integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;
  return query
  select r.id, r.listing_id, l.title,
         coalesce(nullif(o.hostel_name, ''), o.full_name),
         r.reason, r.details, r.created_at,
         (select count(*)::integer from public.reports x
            where x.listing_id = r.listing_id and x.status = 'open')
  from public.reports r
  join public.listings l on l.id = r.listing_id
  join public.profiles o on o.id = l.owner_id
  where r.status = 'open'
  order by r.created_at;
end;
$function$;

create or replace function public.admin_report_action(p_report uuid, p_takedown boolean, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  rep public.reports;
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;
  select * into rep from public.reports where id = p_report;
  if rep.id is null then
    raise exception 'Report not found.';
  end if;

  if p_takedown then
    update public.listings
    set status = 'rejected', reject_note = left(coalesce(p_note, 'Taken down after a report'), 300)
    where id = rep.listing_id;
    update public.reports set status = 'actioned'
    where listing_id = rep.listing_id and status = 'open';
  else
    update public.reports set status = 'dismissed' where id = rep.id;
  end if;
end;
$function$;


-- ============================================================
-- PART 9: Admin tools
-- Lists and actions for the admin dashboard.
-- ============================================================

create or replace function public.admin_users()
 RETURNS TABLE(id uuid, full_name text, hostel_name text, email text, role text, status text, approved boolean, trusted boolean, credit_frozen boolean, warnings integer, joined timestamp with time zone, credits_used integer, listing_count integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;
  return query
  select p.id, p.full_name, p.hostel_name, u.email::text, p.role,
         p.status, p.approved, p.trusted, p.credit_frozen, p.warnings, u.created_at,
         (select count(*)::integer from public.credits c
            where c.student_id = p.id and c.created_at > now() - interval '120 days'),
         (select count(*)::integer from public.listings l where l.owner_id = p.id)
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.role <> 'admin'
  order by u.created_at desc;
end;
$function$;

create or replace function public.admin_user_action(p_user uuid, p_action text, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  target public.profiles;
  r public.reservations;
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;
  select * into target from public.profiles where id = p_user;
  if target.id is null or target.role = 'admin' then
    raise exception 'User not found.';
  end if;

  if p_action = 'warn' then
    update public.profiles set warnings = warnings + 1 where id = p_user;
  elsif p_action = 'freeze' then
    update public.profiles set credit_frozen = true where id = p_user;
  elsif p_action = 'ban' then
    update public.profiles set status = 'banned' where id = p_user;
    if target.role <> 'student' then
      -- Students who reserved this owner's rooms get their fee back as credit
      for r in
        select res.* from public.reservations res
        join public.listings l on l.id = res.listing_id
        where l.owner_id = p_user and res.status in ('held', 'claimed', 'disputed')
      loop
        perform public.give_credit(r.id, 'admin');
      end loop;
      -- and every listing of the owner is removed from the site
      update public.listings
      set status = 'rejected', reject_note = 'Account banned'
      where owner_id = p_user and status <> 'rejected';
    end if;
  elsif p_action = 'unban' then
    update public.profiles set status = 'active' where id = p_user;
  elsif p_action = 'trusted_on' then
    update public.profiles set trusted = true where id = p_user;
  elsif p_action = 'trusted_off' then
    update public.profiles set trusted = false where id = p_user;
  elsif p_action = 'approve' then
    update public.profiles set approved = true where id = p_user;
  elsif p_action = 'unapprove' then
    update public.profiles set approved = false where id = p_user;
  else
    raise exception 'Unknown action.';
  end if;

  insert into public.admin_log (admin_id, user_id, action, note)
  values (auth.uid(), p_user, p_action, p_note);
end;
$function$;

create or replace function public.admin_disputes()
 RETURNS TABLE(id uuid, student_name text, owner_name text, room_title text, claim_reasons text[], claim_note text, claimed_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;
  return query
  select r.id, s.full_name, r.owner_name, r.room_title,
         r.claim_reasons, r.claim_note, r.claimed_at
  from public.reservations r
  join public.profiles s on s.id = r.student_id
  where r.status = 'disputed'
  order by r.claimed_at;
end;
$function$;

create or replace function public.admin_fees()
 RETURNS TABLE(id uuid, reference text, student_name text, room_title text, created_at timestamp with time zone, amount integer, status text, paid_with text, expires_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;
  return query
  select r.id, r.reference, s.full_name, r.room_title,
         r.created_at, r.amount, r.status, r.paid_with, r.expires_at
  from public.reservations r
  join public.profiles s on s.id = r.student_id
  order by r.created_at desc;
end;
$function$;

create or replace function public.admin_inbox()
 RETURNS TABLE(id uuid, kind text, user_id uuid, name text, email text, body text, status text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;
  return query
  select i.id, i.kind, i.user_id, i.name, i.email, i.body, i.status, i.created_at
  from public.inbox i
  order by (i.status = 'new') desc, i.created_at desc;
end;
$function$;

create or replace function public.admin_inbox_action(p_id uuid, p_decision text, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  item public.inbox;
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;
  select * into item from public.inbox where id = p_id;
  if item.id is null then
    raise exception 'Message not found.';
  end if;

  if p_decision = 'done' and item.kind = 'contact' then
    update public.inbox set status = 'done' where id = p_id;
  elsif p_decision = 'restore' and item.kind = 'appeal' then
    update public.profiles set status = 'active' where id = item.user_id;
    update public.inbox set status = 'restored' where id = p_id;
    insert into public.admin_log (admin_id, user_id, action, note)
    values (auth.uid(), item.user_id, 'unban', coalesce(p_note, 'Appeal accepted'));
  elsif p_decision = 'reject' and item.kind = 'appeal' then
    update public.inbox set status = 'rejected' where id = p_id;
    insert into public.admin_log (admin_id, user_id, action, note)
    values (auth.uid(), item.user_id, 'appeal_rejected', p_note);
  else
    raise exception 'Unknown decision.';
  end if;
end;
$function$;


-- ============================================================
-- PART 10: Profile, contact and appeals
-- ============================================================

create or replace function public.my_profile()
 RETURNS TABLE(full_name text, email text, phone text, matric text, hostel_name text, role text, bank_name text, account_number text, account_name text, notify_rooms boolean, notify_tips boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.full_name, u.email::text, p.phone, p.matric, p.hostel_name, p.role,
         p.bank_name, p.account_number, p.account_name, p.notify_rooms, p.notify_tips
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.id = auth.uid();
$function$;

create or replace function public.save_profile(p_name text, p_phone text, p_matric text, p_hostel text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me public.profiles;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null then
    raise exception 'Please log in.';
  end if;
  if char_length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'Please enter your full name.';
  end if;
  update public.profiles
  set full_name = left(trim(p_name), 100),
      phone = nullif(left(trim(coalesce(p_phone, '')), 20), ''),
      matric = case when role = 'student' then nullif(left(trim(coalesce(p_matric, '')), 30), '') else matric end,
      hostel_name = case when role = 'hostel' then nullif(left(trim(coalesce(p_hostel, '')), 100), '') else hostel_name end
  where id = auth.uid();
end;
$function$;

create or replace function public.save_payout(p_bank text, p_number text, p_name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me public.profiles;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null or me.role = 'student' then
    raise exception 'Only owners and hostel managers have a payout account.';
  end if;
  if coalesce(p_number, '') !~ '^[0-9]{10}$' then
    raise exception 'The account number must be 10 digits.';
  end if;
  update public.profiles
  set bank_name = left(trim(coalesce(p_bank, '')), 60),
      account_number = p_number,
      account_name = left(trim(coalesce(p_name, '')), 100)
  where id = auth.uid();
end;
$function$;

create or replace function public.save_notify(p_rooms boolean, p_tips boolean)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update public.profiles set notify_rooms = coalesce(p_rooms, false), notify_tips = coalesce(p_tips, false)
  where id = auth.uid();
$function$;

create or replace function public.delete_my_account()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me public.profiles;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null then
    raise exception 'Please log in.';
  end if;
  if me.role = 'admin' then
    raise exception 'Admin accounts cannot be deleted here.';
  end if;
  if exists (select 1 from public.reservations
             where student_id = me.id and status in ('held', 'claimed', 'disputed')) then
    raise exception 'You have a room on hold. Finish that first.';
  end if;
  if exists (select 1 from public.credits where student_id = me.id and status = 'available') then
    raise exception 'You still have unused credit. Use it first.';
  end if;
  if exists (select 1 from public.reservations r
             join public.listings l on l.id = r.listing_id
             where l.owner_id = me.id and r.status in ('held', 'claimed', 'disputed')) then
    raise exception 'A student has one of your rooms on hold. Wait until that is finished.';
  end if;
  delete from auth.users where id = me.id;
end;
$function$;

create or replace function public.send_contact(p_name text, p_email text, p_message text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if char_length(trim(coalesce(p_name, ''))) < 2
     or coalesce(p_email, '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
     or char_length(trim(coalesce(p_message, ''))) < 2 then
    raise exception 'Please fill in your name, email and message.';
  end if;
  if (select count(*) from public.inbox
      where kind = 'contact' and email = lower(trim(p_email))
        and created_at > now() - interval '1 hour') >= 3 then
    raise exception 'Too many messages. Please try again later.';
  end if;
  insert into public.inbox (kind, user_id, name, email, body)
  values ('contact', auth.uid(), left(trim(p_name), 100), lower(trim(p_email)), left(trim(p_message), 2000));
end;
$function$;

create or replace function public.my_ban_info()
 RETURNS TABLE(reason text, appeal_sent boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    coalesce((select a.note from public.admin_log a
              where a.user_id = auth.uid() and a.action = 'ban'
              order by a.created_at desc limit 1), 'No reason was written.'),
    exists (select 1 from public.inbox i
            where i.user_id = auth.uid() and i.kind = 'appeal' and i.status = 'new')
  where exists (select 1 from public.profiles p where p.id = auth.uid() and p.status = 'banned');
$function$;

create or replace function public.send_appeal(p_text text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me public.profiles;
begin
  select * into me from public.profiles where id = auth.uid();
  if me.id is null or me.status <> 'banned' then
    raise exception 'Your account is not banned.';
  end if;
  if char_length(trim(coalesce(p_text, ''))) < 2 then
    raise exception 'Please write a few words first.';
  end if;
  if exists (select 1 from public.inbox where user_id = me.id and kind = 'appeal' and status = 'new') then
    raise exception 'You already sent an appeal. An admin will read it.';
  end if;
  insert into public.inbox (kind, user_id, name, email, body)
  values ('appeal', me.id, me.full_name,
          (select email::text from auth.users where id = me.id), left(trim(p_text), 2000));
end;
$function$;


-- ============================================================
-- PART 11: Notifications
-- Automatic messages for payments, credit and listing decisions.
-- ============================================================

create or replace function public.notify(p_user uuid, p_icon text, p_title text, p_body text, p_link text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  insert into public.notifications (user_id, icon, title, body, link)
  values (p_user, p_icon, p_title, p_body, p_link);
$function$;

create or replace function public.mark_notifications_read()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update public.notifications set is_read = true where user_id = auth.uid() and not is_read;
$function$;

create or replace function public.notify_reservation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  owner uuid;
begin
  select owner_id into owner from public.listings where id = new.listing_id;

  if tg_op = 'INSERT' then
    perform public.notify(new.student_id, 'ok', 'Payment confirmed',
      new.room_title || ' is held for you for 48 hours.', 'reservation.html?id=' || new.id);
    if owner is not null then
      perform public.notify(owner, 'room', 'A student reserved your room',
        new.room_title || ' is now taken.', 'lister.html');
    end if;
  elsif new.status is distinct from old.status then
    if new.status = 'claimed' and owner is not null then
      perform public.notify(owner, 'alert', 'A student says they did not take the room',
        new.room_title || '. Please answer on your dashboard.', 'lister.html');
    elsif new.status = 'credited' then
      perform public.notify(new.student_id, 'money', 'Credit added',
        'Your booking fee for ' || new.room_title || ' is now credit you can use.', 'credit.html');
    end if;
  end if;
  return new;
end;
$function$;

create trigger reservation_notices
  after insert or update on public.reservations
  for each row execute function notify_reservation();

create or replace function public.notify_listing()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status is distinct from old.status then
    if new.status = 'live' and old.status = 'pending' then
      perform public.notify(new.owner_id, 'ok', 'Listing approved',
        new.title || ' is now live.', 'lister.html');
    elsif new.status = 'rejected' then
      perform public.notify(new.owner_id, 'alert', 'Listing rejected',
        new.title || coalesce('. ' || new.reject_note, ''), 'lister.html');
    end if;
  end if;
  return new;
end;
$function$;

create trigger listing_notices
  after update on public.listings
  for each row execute function notify_listing();



-- ============================================================
-- PART 12: Permissions
-- Who is allowed to call each function.
-- Only logged-in users can call most of them. Internal ones can be called by nobody.
-- ============================================================

-- Start from nothing for every function
revoke all on function public.give_credit(uuid, text) from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.listing_rules() from public, anon, authenticated;
revoke all on function public.notify(uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function public.notify_listing() from public, anon, authenticated;
revoke all on function public.notify_reservation() from public, anon, authenticated;
revoke all on function public.send_contact(text, text, text) from public, anon, authenticated;
revoke all on function public.admin_disputes() from public, anon, authenticated;
revoke all on function public.admin_fees() from public, anon, authenticated;
revoke all on function public.admin_inbox() from public, anon, authenticated;
revoke all on function public.admin_inbox_action(uuid, text, text) from public, anon, authenticated;
revoke all on function public.admin_report_action(uuid, boolean, text) from public, anon, authenticated;
revoke all on function public.admin_reports() from public, anon, authenticated;
revoke all on function public.admin_resolve_claim(uuid, boolean) from public, anon, authenticated;
revoke all on function public.admin_user_action(uuid, text, text) from public, anon, authenticated;
revoke all on function public.admin_users() from public, anon, authenticated;
revoke all on function public.can_list() from public, anon, authenticated;
revoke all on function public.cancel_reservation(uuid) from public, anon, authenticated;
revoke all on function public.claim_credit(uuid, text[], text) from public, anon, authenticated;
revoke all on function public.credits_this_semester() from public, anon, authenticated;
revoke all on function public.delete_my_account() from public, anon, authenticated;
revoke all on function public.is_admin() from public, anon, authenticated;
revoke all on function public.is_approved_hostel() from public, anon, authenticated;
revoke all on function public.live_rooms() from public, anon, authenticated;
revoke all on function public.mark_notifications_read() from public, anon, authenticated;
revoke all on function public.mark_rent_paid(uuid) from public, anon, authenticated;
revoke all on function public.my_ban_info() from public, anon, authenticated;
revoke all on function public.my_credit_balance() from public, anon, authenticated;
revoke all on function public.my_profile() from public, anon, authenticated;
revoke all on function public.my_reservation(uuid) from public, anon, authenticated;
revoke all on function public.owner_answer_claim(uuid, boolean) from public, anon, authenticated;
revoke all on function public.owner_claims() from public, anon, authenticated;
revoke all on function public.owner_info(uuid) from public, anon, authenticated;
revoke all on function public.process_expired_holds() from public, anon, authenticated;
revoke all on function public.report_listing(uuid, text, text) from public, anon, authenticated;
revoke all on function public.report_no_show(uuid, text, text) from public, anon, authenticated;
revoke all on function public.reserve_room(uuid, boolean) from public, anon, authenticated;
revoke all on function public.save_notify(boolean, boolean) from public, anon, authenticated;
revoke all on function public.save_payout(text, text, text) from public, anon, authenticated;
revoke all on function public.save_profile(text, text, text, text) from public, anon, authenticated;
revoke all on function public.send_appeal(text) from public, anon, authenticated;

-- Logged-in people
grant execute on function public.admin_disputes() to authenticated;
grant execute on function public.admin_fees() to authenticated;
grant execute on function public.admin_inbox() to authenticated;
grant execute on function public.admin_inbox_action(uuid, text, text) to authenticated;
grant execute on function public.admin_report_action(uuid, boolean, text) to authenticated;
grant execute on function public.admin_reports() to authenticated;
grant execute on function public.admin_resolve_claim(uuid, boolean) to authenticated;
grant execute on function public.admin_user_action(uuid, text, text) to authenticated;
grant execute on function public.admin_users() to authenticated;
grant execute on function public.can_list() to authenticated;
grant execute on function public.cancel_reservation(uuid) to authenticated;
grant execute on function public.claim_credit(uuid, text[], text) to authenticated;
grant execute on function public.credits_this_semester() to authenticated;
grant execute on function public.delete_my_account() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_approved_hostel() to authenticated;
grant execute on function public.live_rooms() to authenticated;
grant execute on function public.mark_notifications_read() to authenticated;
grant execute on function public.mark_rent_paid(uuid) to authenticated;
grant execute on function public.my_ban_info() to authenticated;
grant execute on function public.my_credit_balance() to authenticated;
grant execute on function public.my_profile() to authenticated;
grant execute on function public.my_reservation(uuid) to authenticated;
grant execute on function public.owner_answer_claim(uuid, boolean) to authenticated;
grant execute on function public.owner_claims() to authenticated;
grant execute on function public.owner_info(uuid) to authenticated;
grant execute on function public.process_expired_holds() to authenticated;
grant execute on function public.report_listing(uuid, text, text) to authenticated;
grant execute on function public.report_no_show(uuid, text, text) to authenticated;
grant execute on function public.reserve_room(uuid, boolean) to authenticated;
grant execute on function public.save_notify(boolean, boolean) to authenticated;
grant execute on function public.save_payout(text, text, text) to authenticated;
grant execute on function public.save_profile(text, text, text, text) to authenticated;
grant execute on function public.send_appeal(text) to authenticated;
grant execute on function public.send_contact(text, text, text) to authenticated;

-- Visitors who are not logged in (the contact form)
grant execute on function public.send_contact(text, text, text) to anon;


-- ============================================================
-- PART 13: Make yourself admin
-- Run this on its own AFTER you have signed up.
-- Remove the two dashes at the start of each line and put your own email between the quotes.
-- ============================================================

-- update public.profiles
-- set role = 'admin', approved = true
-- where id = (select id from auth.users where email = 'PUT-YOUR-EMAIL-HERE');
