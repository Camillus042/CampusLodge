-- ============================================================
-- CampusLodge database, part 11: admin tools and listing reports
-- Paste this whole file into a NEW query in Supabase > SQL Editor > Run
-- ============================================================

alter table public.profiles
  add column if not exists warnings integer not null default 0;

-- ------------------------------------------------------------
-- A record of what admins did (shown to nobody but admins)
-- ------------------------------------------------------------
create table public.admin_log (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid references public.profiles(id) on delete set null,
  user_id uuid references public.profiles(id) on delete cascade,
  action text not null,
  note text,
  created_at timestamptz not null default now()
);
alter table public.admin_log enable row level security;
create policy "admin reads log"
  on public.admin_log for select
  to authenticated
  using (public.is_admin());
grant select on public.admin_log to authenticated;

-- ------------------------------------------------------------
-- Reports on listings
-- ------------------------------------------------------------
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (reason in ('fake', 'wrong', 'outside', 'taken', 'other')),
  details text,
  status text not null default 'open' check (status in ('open', 'dismissed', 'actioned')),
  created_at timestamptz not null default now()
);
alter table public.reports enable row level security;
create policy "admin reads reports"
  on public.reports for select
  to authenticated
  using (public.is_admin());
grant select on public.reports to authenticated;

-- Any logged-in person can report a live room (one open report each)
create or replace function public.report_listing(p_listing uuid, p_reason text, p_details text)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;
revoke all on function public.report_listing(uuid, text, text) from public, anon;
grant execute on function public.report_listing(uuid, text, text) to authenticated;

-- ------------------------------------------------------------
-- Admin lists
-- ------------------------------------------------------------
create or replace function public.admin_users()
returns table (
  id uuid, full_name text, hostel_name text, email text, role text,
  status text, approved boolean, trusted boolean, credit_frozen boolean,
  warnings integer, joined timestamptz, credits_used integer, listing_count integer
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
$$;

create or replace function public.admin_reports()
returns table (
  id uuid, listing_id uuid, listing_title text, owner_name text,
  reason text, details text, created_at timestamptz, report_count integer
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
$$;

create or replace function public.admin_disputes()
returns table (
  id uuid, student_name text, owner_name text, room_title text,
  claim_reasons text[], claim_note text, claimed_at timestamptz
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
  select r.id, s.full_name, r.owner_name, r.room_title,
         r.claim_reasons, r.claim_note, r.claimed_at
  from public.reservations r
  join public.profiles s on s.id = r.student_id
  where r.status = 'disputed'
  order by r.claimed_at;
end;
$$;

create or replace function public.admin_fees()
returns table (
  id uuid, reference text, student_name text, room_title text,
  created_at timestamptz, amount integer, status text, paid_with text, expires_at timestamptz
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
  select r.id, r.reference, s.full_name, r.room_title,
         r.created_at, r.amount, r.status, r.paid_with, r.expires_at
  from public.reservations r
  join public.profiles s on s.id = r.student_id
  order by r.created_at desc;
end;
$$;

revoke all on function public.admin_users() from public, anon;
revoke all on function public.admin_reports() from public, anon;
revoke all on function public.admin_disputes() from public, anon;
revoke all on function public.admin_fees() from public, anon;
grant execute on function public.admin_users() to authenticated;
grant execute on function public.admin_reports() to authenticated;
grant execute on function public.admin_disputes() to authenticated;
grant execute on function public.admin_fees() to authenticated;

-- ------------------------------------------------------------
-- Admin actions on users
-- ------------------------------------------------------------
create or replace function public.admin_user_action(p_user uuid, p_action text, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;
revoke all on function public.admin_user_action(uuid, text, text) from public, anon;
grant execute on function public.admin_user_action(uuid, text, text) to authenticated;

-- ------------------------------------------------------------
-- Admin actions on reports
-- ------------------------------------------------------------
create or replace function public.admin_report_action(p_report uuid, p_takedown boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;
revoke all on function public.admin_report_action(uuid, boolean, text) from public, anon;
grant execute on function public.admin_report_action(uuid, boolean, text) to authenticated;
