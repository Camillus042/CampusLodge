-- ============================================================
-- CampusLodge database, part 12: profile, contact, appeals, notifications
-- Paste this whole file into a NEW query in Supabase > SQL Editor > Run
-- ============================================================

-- ------------------------------------------------------------
-- Extra details on a profile
-- ------------------------------------------------------------
alter table public.profiles
  add column if not exists matric text,
  add column if not exists bank_name text,
  add column if not exists account_number text,
  add column if not exists account_name text,
  add column if not exists notify_rooms boolean not null default true,
  add column if not exists notify_tips boolean not null default false;

-- Everything the profile page needs, in one call
create or replace function public.my_profile()
returns table (
  full_name text, email text, phone text, matric text, hostel_name text, role text,
  bank_name text, account_number text, account_name text,
  notify_rooms boolean, notify_tips boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select p.full_name, u.email::text, p.phone, p.matric, p.hostel_name, p.role,
         p.bank_name, p.account_number, p.account_name, p.notify_rooms, p.notify_tips
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.id = auth.uid();
$$;

create or replace function public.save_profile(p_name text, p_phone text, p_matric text, p_hostel text)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

create or replace function public.save_payout(p_bank text, p_number text, p_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

create or replace function public.save_notify(p_rooms boolean, p_tips boolean)
returns void
language sql
security definer
set search_path = public
as $$
  update public.profiles set notify_rooms = coalesce(p_rooms, false), notify_tips = coalesce(p_tips, false)
  where id = auth.uid();
$$;

-- ------------------------------------------------------------
-- Delete my account (refused while money or a room is in play)
-- ------------------------------------------------------------
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

-- ------------------------------------------------------------
-- Contact messages and ban appeals (read by admins only)
-- ------------------------------------------------------------
create table if not exists public.inbox (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('contact', 'appeal')),
  user_id uuid references public.profiles(id) on delete cascade,
  name text,
  email text,
  body text not null check (char_length(body) between 2 and 2000),
  status text not null default 'new' check (status in ('new', 'done', 'restored', 'rejected')),
  created_at timestamptz not null default now()
);
alter table public.inbox enable row level security;
create policy "admin reads inbox"
  on public.inbox for select
  to authenticated
  using (public.is_admin());
grant select on public.inbox to authenticated;

-- Anyone (even logged out) can send a contact message
create or replace function public.send_contact(p_name text, p_email text, p_message text)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;
revoke all on function public.send_contact(text, text, text) from public;
grant execute on function public.send_contact(text, text, text) to anon, authenticated;

-- What the banned person sees on the appeal page
create or replace function public.my_ban_info()
returns table (reason text, appeal_sent boolean)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce((select a.note from public.admin_log a
              where a.user_id = auth.uid() and a.action = 'ban'
              order by a.created_at desc limit 1), 'No reason was written.'),
    exists (select 1 from public.inbox i
            where i.user_id = auth.uid() and i.kind = 'appeal' and i.status = 'new')
  where exists (select 1 from public.profiles p where p.id = auth.uid() and p.status = 'banned');
$$;

create or replace function public.send_appeal(p_text text)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

create or replace function public.admin_inbox()
returns table (
  id uuid, kind text, user_id uuid, name text, email text, body text,
  status text, created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;
  return query
  select i.id, i.kind, i.user_id, i.name, i.email, i.body, i.status, i.created_at
  from public.inbox i
  order by (i.status = 'new') desc, i.created_at desc;
end;
$$;

-- decision: done (contact message answered), restore or reject (appeal)
create or replace function public.admin_inbox_action(p_id uuid, p_decision text, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;

-- ------------------------------------------------------------
-- Notifications
-- ------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  icon text not null default 'info',
  title text not null,
  body text,
  link text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications (user_id, created_at desc);
alter table public.notifications enable row level security;
create policy "read own notifications"
  on public.notifications for select
  to authenticated
  using (user_id = auth.uid());
grant select on public.notifications to authenticated;

create or replace function public.mark_notifications_read()
returns void
language sql
security definer
set search_path = public
as $$
  update public.notifications set is_read = true where user_id = auth.uid() and not is_read;
$$;

create or replace function public.notify(p_user uuid, p_icon text, p_title text, p_body text, p_link text)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.notifications (user_id, icon, title, body, link)
  values (p_user, p_icon, p_title, p_body, p_link);
$$;
revoke all on function public.notify(uuid, text, text, text, text) from public, anon, authenticated;

-- A reservation is made or changes: tell the student and the owner
create or replace function public.notify_reservation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;

drop trigger if exists reservation_notices on public.reservations;
create trigger reservation_notices
  after insert or update on public.reservations
  for each row execute function public.notify_reservation();

-- A listing is approved or rejected: tell the owner
create or replace function public.notify_listing()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;

drop trigger if exists listing_notices on public.listings;
create trigger listing_notices
  after update on public.listings
  for each row execute function public.notify_listing();

-- ------------------------------------------------------------
-- Who may call what
-- ------------------------------------------------------------
revoke all on function public.my_profile() from public, anon;
revoke all on function public.save_profile(text, text, text, text) from public, anon;
revoke all on function public.save_payout(text, text, text) from public, anon;
revoke all on function public.save_notify(boolean, boolean) from public, anon;
revoke all on function public.delete_my_account() from public, anon;
revoke all on function public.my_ban_info() from public, anon;
revoke all on function public.send_appeal(text) from public, anon;
revoke all on function public.admin_inbox() from public, anon;
revoke all on function public.admin_inbox_action(uuid, text, text) from public, anon;
revoke all on function public.mark_notifications_read() from public, anon;
grant execute on function public.my_profile() to authenticated;
grant execute on function public.save_profile(text, text, text, text) to authenticated;
grant execute on function public.save_payout(text, text, text) to authenticated;
grant execute on function public.save_notify(boolean, boolean) to authenticated;
grant execute on function public.delete_my_account() to authenticated;
grant execute on function public.my_ban_info() to authenticated;
grant execute on function public.send_appeal(text) to authenticated;
grant execute on function public.admin_inbox() to authenticated;
grant execute on function public.admin_inbox_action(uuid, text, text) to authenticated;
grant execute on function public.mark_notifications_read() to authenticated;
