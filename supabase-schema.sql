-- ============================================================
--  Zeus AI Hub — Supabase schema
--  Run once: Supabase dashboard → SQL Editor → New query → paste → Run.
--  IMPORTANT: edit the seed email in section 4 to YOUR email before running,
--  otherwise you won't be able to log in.
-- ============================================================

-- 1. TABLES ---------------------------------------------------------------
create table if not exists public.employees (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  email         text not null unique,
  designation   text,
  department    text,
  tracking_area text,
  work_status   text default 'Available',
  created_at    timestamptz default now()
);

create table if not exists public.clients (
  id              uuid primary key default gen_random_uuid(),
  company         text not null,
  primary_contact text,
  created_at      timestamptz default now()
);

create table if not exists public.tasks (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  client_id  uuid references public.clients(id) on delete cascade,
  due_date   date,
  status     text default 'Not Started',
  raci       jsonb not null default '{}'::jsonb,   -- { "<employee_id>": "R" | "A" | "C" | "I" }
  created_at timestamptz default now()
);

create table if not exists public.shifts (
  id          uuid primary key default gen_random_uuid(),
  employee_id uuid references public.employees(id) on delete cascade,
  day         text not null,          -- Mon..Sun
  start_time  text not null,          -- "09:00"
  end_time    text not null,          -- "17:00"
  area        text
);

create table if not exists public.logs (
  id          uuid primary key default gen_random_uuid(),
  employee_id uuid references public.employees(id) on delete cascade,
  clock_in    timestamptz not null default now(),
  clock_out   timestamptz,            -- null while on the clock
  area        text
);

-- 2. ACCESS CONTROL -------------------------------------------------------
-- Only people whose email is in the employees table may read/write anything.
-- SECURITY DEFINER lets this read employees without tripping recursive RLS.
create or replace function public.is_team_member()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.employees
    where lower(email) = lower(auth.jwt() ->> 'email')
  );
$$;

alter table public.employees enable row level security;
alter table public.clients   enable row level security;
alter table public.tasks     enable row level security;
alter table public.shifts    enable row level security;
alter table public.logs      enable row level security;

do $$
declare t text;
begin
  foreach t in array array['employees','clients','tasks','shifts','logs'] loop
    execute format('drop policy if exists team_all on public.%I;', t);
    execute format(
      'create policy team_all on public.%I for all to authenticated
         using (public.is_team_member()) with check (public.is_team_member());', t);
  end loop;
end $$;

-- 3. REALTIME (live updates across everyone's screens) --------------------
-- Safe to ignore an "already member of publication" error if you re-run this.
alter publication supabase_realtime add table
  public.employees, public.clients, public.tasks, public.shifts, public.logs;

-- 4. SEED — add yourself so you can log in  ◀◀◀ EDIT THE EMAIL ◀◀◀ ---------
insert into public.employees (name, email, designation, department, tracking_area, work_status)
values ('Your Name', 'you@yourcompany.com', 'Project Manager', 'Operations', 'Office HQ', 'Active')
on conflict (email) do nothing;

-- (Optional) add the rest of your team here, or add them later from the app's
-- Staff Directory once you're logged in:
-- insert into public.employees (name, email, designation, department, tracking_area, work_status) values
--   ('Ava Chen',   'ava@yourcompany.com',   'AI Engineer',     'Engineering', 'Remote',   'Active'),
--   ('Marcus Reid','marcus@yourcompany.com','Project Manager', 'Delivery',    'Office HQ','Active')
-- on conflict (email) do nothing;
