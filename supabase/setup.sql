-- Trip Expense Ledger: database setup for Supabase.
-- Run this in your Supabase project: Dashboard -> SQL Editor -> New query -> paste -> Run.
-- BEFORE RUNNING: at the bottom, replace PIN_FOR_USER1 ... PIN_FOR_USER4 with each person's PIN.
-- Every PIN must be different. Safe to run again: it keeps existing expenses.
-- To change a PIN later, run only the last "insert ... on conflict" statement again.

create extension if not exists pgcrypto with schema extensions;

-- Remove the earlier single-passcode version, if it was installed.
drop function if exists public.verify_pass(text);
drop function if exists public.list_expenses(text);
drop function if exists public.get_image(text, uuid);
drop function if exists public.save_expense(text, jsonb);
drop function if exists public.delete_expense(text, uuid);
drop function if exists public.login(text);
drop function if exists public.delete_all(text);
drop function if exists public._require_pass(text);
drop function if exists public._user(text);
drop table if exists public.app_secret;

-- Tables -------------------------------------------------------------------

create table if not exists public.users (
  name text primary key,
  pin_hash text not null,
  shares boolean not null default true,   -- true = splits the total spending
  sort int not null default 0
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  person text not null,                    -- who paid (set from the PIN, not typed)
  date date not null,
  cat text not null check (cat in ('meal', 'taxi', 'other')),
  merch text,
  items jsonb not null default '[]'::jsonb,
  total numeric not null check (total > 0),
  cur text not null,
  pay text not null default 'personal',
  rcpt boolean not null default true,
  note text,
  img text,                                -- small JPEG receipt photo as a data: URL
  scanned boolean not null default false
);
alter table public.expenses alter column pay set default 'personal';
alter table public.expenses add column if not exists lat double precision;  -- where the receipt was scanned
alter table public.expenses add column if not exists lng double precision;

alter table public.users add column if not exists can_delete_all boolean not null default false;  -- may use DELETE ALL

-- Lock the tables: the website can never read or write them directly,
-- only through the functions below, which check the PIN first.
alter table public.users enable row level security;
alter table public.expenses enable row level security;
revoke all on public.users from anon, authenticated;
revoke all on public.expenses from anon, authenticated;

-- PIN check ----------------------------------------------------------------

create function public._user(p text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare u text;
begin
  if p is not null then
    select name into u from public.users where pin_hash = crypt(p, pin_hash) limit 1;
  end if;
  if u is null then
    perform pg_sleep(1);  -- slows down guessing
    raise exception 'wrong PIN' using errcode = '28P01';
  end if;
  return u;
end $$;
revoke all on function public._user(text) from public, anon, authenticated;

-- Returns {"name": "user1", "users": [{"name": "user1", "shares": true}, ...]} or null for a wrong PIN.
create function public.login(p text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u text;
begin
  u := public._user(p);
  return jsonb_build_object(
    'name', u,
    'can_delete_all', (select can_delete_all from public.users where name = u),
    'users', (select jsonb_agg(jsonb_build_object('name', name, 'shares', shares) order by sort, name) from public.users)
  );
exception when sqlstate '28P01' then
  return null;
end $$;

-- Read ---------------------------------------------------------------------

create function public.list_expenses(p text)
returns table (
  id uuid, created_at timestamptz, person text, date date, cat text, merch text,
  items jsonb, total numeric, cur text, note text, scanned boolean, has_img boolean,
  lat double precision, lng double precision
)
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public._user(p);
  return query
    select e.id, e.created_at, e.person, e.date, e.cat, e.merch, e.items, e.total, e.cur,
           e.note, e.scanned, (e.img is not null), e.lat, e.lng
    from public.expenses e
    order by e.date desc, e.created_at desc;
end $$;

create function public.get_image(p text, eid uuid) returns text
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public._user(p);
  return (select e.img from public.expenses e where e.id = eid);
end $$;

-- Write (each person can change only what they entered) --------------------

create function public.save_expense(p text, e jsonb) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  u text;
  new_id uuid;
  v_img text := e->>'img';
  v_keep boolean := coalesce((e->>'keep_img')::boolean, false);
  v_total numeric := (e->>'total')::numeric;
begin
  u := public._user(p);
  if v_total is null or v_total <= 0 then
    raise exception 'The total must be more than zero.';
  end if;
  if v_img is not null and (length(v_img) > 300000 or v_img not like 'data:image/jpeg;base64,%') then
    raise exception 'The receipt photo is too large or not a JPEG.';
  end if;

  if coalesce(e->>'id', '') = '' then
    insert into public.expenses (person, date, cat, merch, items, total, cur, note, img, scanned, lat, lng)
    values (
      u,
      (e->>'date')::date,
      e->>'cat',
      left(e->>'merch', 80),
      coalesce(e->'items', '[]'::jsonb),
      v_total,
      upper(left(coalesce(e->>'cur', 'RMB'), 3)),
      left(e->>'note', 200),
      v_img,
      coalesce((e->>'scanned')::boolean, false),
      (e->>'lat')::double precision,
      (e->>'lng')::double precision
    )
    returning id into new_id;
  else
    update public.expenses x set
      date = (e->>'date')::date,
      cat = e->>'cat',
      merch = left(e->>'merch', 80),
      items = coalesce(e->'items', '[]'::jsonb),
      total = v_total,
      cur = upper(left(coalesce(e->>'cur', x.cur), 3)),
      note = left(e->>'note', 200),
      img = case when v_keep then x.img else v_img end,
      scanned = coalesce((e->>'scanned')::boolean, false),
      lat = (e->>'lat')::double precision,
      lng = (e->>'lng')::double precision,
      updated_at = now()
    where x.id = (e->>'id')::uuid and x.person = u
    returning x.id into new_id;
    if new_id is null then
      raise exception 'You can only change records you entered. Refresh the list.';
    end if;
  end if;
  return new_id;
end $$;

create function public.delete_expense(p text, eid uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare u text;
begin
  u := public._user(p);
  delete from public.expenses where id = eid and person = u;
  if not found then
    raise exception 'You can only delete records you entered.';
  end if;
end $$;

-- Deletes every record from every user. Only users with can_delete_all may do this. Returns how many were deleted.
create function public.delete_all(p text) returns integer
language plpgsql security definer set search_path = public, extensions as $$
declare n integer; u text;
begin
  u := public._user(p);
  if not exists (select 1 from public.users where name = u and can_delete_all) then
    raise exception 'Only user2 can delete all records.';
  end if;
  delete from public.expenses where true;
  get diagnostics n = row_count;
  return n;
end $$;

grant execute on function public.login(text) to anon;
grant execute on function public.delete_all(text) to anon;
grant execute on function public.list_expenses(text) to anon;
grant execute on function public.get_image(text, uuid) to anon;
grant execute on function public.save_expense(text, jsonb) to anon;
grant execute on function public.delete_expense(text, uuid) to anon;

-- The four users and their PINs (stored only as bcrypt hashes) -------------
-- user1, user2 and user3 split the total spending; user4 does not. Only user2 may use DELETE ALL.

insert into public.users (name, pin_hash, shares, sort, can_delete_all) values
  ('user1', extensions.crypt('PIN_FOR_USER1', extensions.gen_salt('bf')), true, 1, false),
  ('user2', extensions.crypt('PIN_FOR_USER2', extensions.gen_salt('bf')), true, 2, true),
  ('user3', extensions.crypt('PIN_FOR_USER3', extensions.gen_salt('bf')), true, 3, false),
  ('user4', extensions.crypt('PIN_FOR_USER4', extensions.gen_salt('bf')), false, 4, false)
on conflict (name) do update set pin_hash = excluded.pin_hash, shares = excluded.shares, sort = excluded.sort,
  can_delete_all = excluded.can_delete_all;
