-- ============================================================
--  Zeus AI Hub — Task Tracker v2  (run ONCE, after supabase-schema.sql
--  and supabase-roles.sql)
--
--  Adds a PROJECTS layer (Client → Project → Tasks) and rebuilds the
--  tasks table around the 8-column format:
--    Primary Task · Sub task · Detailed Task · Developer ·
--    Start date · End date · Current status · Checker
--
--  ⚠️  This DROPS and recreates the tasks table — existing tasks are
--      cleared (as agreed). Clients, staff, shifts and logs are untouched.
-- ============================================================

-- 1. PROJECTS (each belongs to a client) -----------------------------------
create table if not exists public.projects (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid references public.clients(id) on delete cascade,
  name        text not null,
  description text,
  status      text default 'Active',
  created_at  timestamptz default now()
);

-- 2. TASKS — rebuilt for the new format ------------------------------------
drop table if exists public.tasks cascade;
create table public.tasks (
  id            uuid primary key default gen_random_uuid(),
  project_id    uuid references public.projects(id) on delete cascade,
  primary_task  text,
  sub_task      text,
  detailed_task text not null,
  developer_id  uuid references public.employees(id) on delete set null,
  checker_id    uuid references public.employees(id) on delete set null,
  start_date    date,
  end_date      date,
  status        text default 'Not Started',
  created_at    timestamptz default now()
);

-- 3. Row-level security ----------------------------------------------------
alter table public.projects enable row level security;
alter table public.tasks    enable row level security;

-- everyone on the roster can read
drop policy if exists read_all on public.projects;
drop policy if exists read_all on public.tasks;
create policy read_all on public.projects for select to authenticated using (public.is_team_member());
create policy read_all on public.tasks    for select to authenticated using (public.is_team_member());

-- admins manage projects and tasks
drop policy if exists proj_write on public.projects;
drop policy if exists task_write on public.tasks;
create policy proj_write on public.projects for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy task_write on public.tasks    for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- 4. Realtime (ignore "already member of publication" if you re-run) -------
do $$
begin
  begin alter publication supabase_realtime add table public.projects; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.tasks;    exception when duplicate_object then null; end;
end $$;

-- 5. Members may change ONLY a task's status (via this function) -----------
create or replace function public.set_task_status(p_task uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_team_member() then raise exception 'Not authorized'; end if;
  if p_status not in ('Not Started','In Progress','In Review','Blocked','Completed') then
    raise exception 'Invalid status';
  end if;
  update public.tasks set status = p_status where id = p_task;
end;
$$;
grant execute on function public.set_task_status(uuid, text) to authenticated;
