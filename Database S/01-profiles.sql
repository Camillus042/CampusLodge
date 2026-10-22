-- ============================================================
-- CampusLodge database, part 1: people (profiles)
-- Paste this whole file into Supabase > SQL Editor > Run
-- ============================================================

-- One row for every account. Supabase keeps the email and password
-- safely in its own table; this table holds everything else.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role text not null default 'student'
    check (role in ('student', 'landlord', 'agent', 'hostel', 'admin')),
  full_name text not null default '',
  phone text,
  hostel_name text,
  hostel_gender text,
  approved boolean not null default false,
  status text not null default 'active'
    check (status in ('active', 'banned')),
  warnings integer not null default 0,
  credit_frozen boolean not null default false,
  created_at timestamptz not null default now()
);

-- One phone number can only belong to one account
create unique index profiles_phone_key
  on public.profiles (phone)
  where phone is not null;

-- ------------------------------------------------------------
-- Helper: is the person asking an active admin?
-- ------------------------------------------------------------
create function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'admin'
      and status = 'active'
  );
$$;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- ------------------------------------------------------------
-- When someone signs up, make their profile automatically.
-- Nobody can sign up as admin, and landlords, agents and hostel
-- managers start as NOT approved until an admin approves them.
-- ------------------------------------------------------------
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  chosen text := coalesce(new.raw_user_meta_data ->> 'role', 'student');
begin
  if chosen not in ('student', 'landlord', 'agent', 'hostel') then
    chosen := 'student';
  end if;

  insert into public.profiles (
    id, role, full_name, phone, hostel_name, hostel_gender, approved
  )
  values (
    new.id,
    chosen,
    left(coalesce(new.raw_user_meta_data ->> 'full_name', ''), 100),
    nullif(left(trim(coalesce(new.raw_user_meta_data ->> 'phone', '')), 20), ''),
    nullif(left(trim(coalesce(new.raw_user_meta_data ->> 'hostel_name', '')), 100), ''),
    nullif(left(trim(coalesce(new.raw_user_meta_data ->> 'hostel_gender', '')), 30), ''),
    chosen = 'student'
  );

  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- ------------------------------------------------------------
-- Security: who can see and change what
-- ------------------------------------------------------------
alter table public.profiles enable row level security;

-- You can see your own profile
create policy "see own profile"
  on public.profiles
  for select
  to authenticated
  using (id = auth.uid());

-- Admins can see everyone
create policy "admin sees all profiles"
  on public.profiles
  for select
  to authenticated
  using (public.is_admin());

-- You can change your own profile...
create policy "change own profile"
  on public.profiles
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ...but only these four boxes. Role, approval, status, warnings and
-- frozen credit can never be changed from the website by the user.
grant usage on schema public to anon, authenticated;
grant select on public.profiles to authenticated;
grant update (full_name, phone, hostel_name, hostel_gender)
  on public.profiles to authenticated;
