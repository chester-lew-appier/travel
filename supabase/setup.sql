-- Trip Expense Ledger: database setup for Supabase.
-- Run this once in your Supabase project: Dashboard -> SQL Editor -> New query -> paste -> Run.
-- BEFORE RUNNING: replace CHANGE_ME (near the bottom) with the passcode your friends will type.
-- To change the passcode later, run only the last "insert ... on conflict" statement again with a new value.

create extension if not exists pgcrypto with schema extensions;

-- Tables -------------------------------------------------------------------

create table if not exists public.app_secret (
  id int primary key default 1 check (id = 1),
  pass_hash text not null
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  person text not null,
  date date not null,
  cat text not null check (cat in ('meal', 'taxi', 'other')),
  merch text,
  items jsonb not null default '[]'::jsonb,
  total numeric not null check (total > 0),
  cur text not null,
  pay text not null check (pay in ('personal', 'corp')),
  rcpt boolean not null default true,
  note text,
  img text,              -- small JPEG receipt photo as a data: URL
  scanned boolean not null default false
);

-- Lock the tables: the website can never read or write them directly,
-- only through the functions below, which check the passcode first.
alter table public.app_secret enable row level security;
alter table public.expenses enable row level security;
revoke all on public.app_secret from anon, authenticated;
revoke all on public.expenses from anon, authenticated;

-- Passcode check -----------------------------------------------------------

create or replace function public._require_pass(p text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if p is null or not exists (
    select 1 from public.app_secret where id = 1 and pass_hash = crypt(p, pass_hash)
  ) then
    perform pg_sleep(1);  -- slows down guessing
    raise exception 'wrong passcode' using errcode = '28P01';
  end if;
end $$;
revoke all on function public._require_pass(text) from public, anon, authenticated;

create or replace function public.verify_pass(p text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public._require_pass(p);
  return true;
exception when sqlstate '28P01' then
  return false;
end $$;

-- Read ---------------------------------------------------------------------

create or replace function public.list_expenses(p text)
returns table (
  id uuid, created_at timestamptz, person text, date date, cat text, merch text,
  items jsonb, total numeric, cur text, pay text, rcpt boolean, note text,
  scanned boolean, has_img boolean
)
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public._require_pass(p);
  return query
    select e.id, e.created_at, e.person, e.date, e.cat, e.merch, e.items, e.total, e.cur,
           e.pay, e.rcpt, e.note, e.scanned, (e.img is not null)
    from public.expenses e
    order by e.date desc, e.created_at desc;
end $$;

create or replace function public.get_image(p text, eid uuid) returns text
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public._require_pass(p);
  return (select e.img from public.expenses e where e.id = eid);
end $$;

-- Write --------------------------------------------------------------------

create or replace function public.save_expense(p text, e jsonb) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare
  new_id uuid;
  v_img text := e->>'img';
  v_keep boolean := coalesce((e->>'keep_img')::boolean, false);
  v_total numeric := (e->>'total')::numeric;
begin
  perform public._require_pass(p);
  if v_total is null or v_total <= 0 then
    raise exception 'The total must be more than zero.';
  end if;
  if v_img is not null and (length(v_img) > 300000 or v_img not like 'data:image/jpeg;base64,%') then
    raise exception 'The receipt photo is too large or not a JPEG.';
  end if;

  if coalesce(e->>'id', '') = '' then
    insert into public.expenses (person, date, cat, merch, items, total, cur, pay, rcpt, note, img, scanned)
    values (
      left(coalesce(nullif(trim(e->>'person'), ''), 'Someone'), 40),
      (e->>'date')::date,
      e->>'cat',
      left(e->>'merch', 80),
      coalesce(e->'items', '[]'::jsonb),
      v_total,
      upper(left(coalesce(e->>'cur', 'TWD'), 3)),
      e->>'pay',
      coalesce((e->>'rcpt')::boolean, true),
      left(e->>'note', 200),
      v_img,
      coalesce((e->>'scanned')::boolean, false)
    )
    returning id into new_id;
  else
    update public.expenses x set
      person = left(coalesce(nullif(trim(e->>'person'), ''), x.person), 40),
      date = (e->>'date')::date,
      cat = e->>'cat',
      merch = left(e->>'merch', 80),
      items = coalesce(e->'items', '[]'::jsonb),
      total = v_total,
      cur = upper(left(coalesce(e->>'cur', x.cur), 3)),
      pay = e->>'pay',
      rcpt = coalesce((e->>'rcpt')::boolean, true),
      note = left(e->>'note', 200),
      img = case when v_keep then x.img else v_img end,
      scanned = coalesce((e->>'scanned')::boolean, false),
      updated_at = now()
    where x.id = (e->>'id')::uuid
    returning x.id into new_id;
    if new_id is null then
      raise exception 'That expense no longer exists. Refresh the list.';
    end if;
  end if;
  return new_id;
end $$;

create or replace function public.delete_expense(p text, eid uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public._require_pass(p);
  delete from public.expenses where id = eid;
end $$;

grant execute on function public.verify_pass(text) to anon;
grant execute on function public.list_expenses(text) to anon;
grant execute on function public.get_image(text, uuid) to anon;
grant execute on function public.save_expense(text, jsonb) to anon;
grant execute on function public.delete_expense(text, uuid) to anon;

-- The passcode (stored only as a bcrypt hash) ------------------------------

insert into public.app_secret (id, pass_hash)
values (1, extensions.crypt('CHANGE_ME', extensions.gen_salt('bf')))
on conflict (id) do update set pass_hash = excluded.pass_hash;
