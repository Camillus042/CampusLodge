-- ============================================================
-- CampusLodge database, part 2: the agreement is checked by the
-- database too, so nobody can skip the tick box.
-- Paste this whole file into Supabase > SQL Editor > Run
-- ============================================================

-- Remember when each person agreed
alter table public.profiles
  add column agreed_at timestamptz;

-- Same sign-up helper as before, but it now refuses anyone who
-- did not agree to the Terms and the Fair Use Agreement.
drop function if exists public.handle_new_user() cascade;

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

-- Connect the helper to new sign-ups again
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
