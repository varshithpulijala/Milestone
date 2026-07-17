-- ============================================================
--  Zeus AI Hub — Role-based access control  (run ONCE, after supabase-schema.sql)
--  Adds Admin vs Member roles and enforces them in the database itself,
--  so permissions can't be bypassed by hiding buttons in the UI.
--  ◀◀◀ EDIT the admin email in section 2 before running. ◀◀◀
-- ============================================================

-- 1. Add a role column -----------------------------------------------------
alter table public.employees add column if not exists role text not null default 'member';

-- 2. Make yourself an admin   ◀◀◀ EDIT EMAIL ◀◀◀ ---------------------------
update public.employees set role = 'admin' where lower(email) = lower('zeusailtd@gmail.com');

-- 3. Helper functions (SECURITY DEFINER = no recursive RLS) -----------------
create or replace function public.is_admin()
returns boolean language sql security definer set search_path = public as $$
  select exists (
    select 1 from public.employees
    where lower(email) = lower(auth.jwt() ->> 'email') and role = 'admin'
  );
$$;

create or replace function public.my_employee_id()
returns uuid language sql security definer set search_path = public as $$
  select id from public.employees
  where lower(email) = lower(auth.jwt() ->> 'email') limit 1;
$$;

-- 4. Replace the old blanket "team_all" policy with granular ones ----------
do $$
declare t text;
begin
  foreach t in array array['employees','clients','tasks','shifts','logs'] loop
    execute format('drop policy if exists team_all on public.%I;', t);
    execute format('drop policy if exists read_all on public.%I;', t);
    -- everyone on the roster can READ everything
    execute format('create policy read_all on public.%I for select to authenticated using (public.is_team_member());', t);
  end loop;
end $$;

-- EMPLOYEES: admins add/remove/edit anyone; a member may edit only their own
--            row, and can never promote themselves to admin.
drop policy if exists emp_insert on public.employees;
drop policy if exists emp_update on public.employees;
drop policy if exists emp_delete on public.employees;
create policy emp_insert on public.employees for insert to authenticated
  with check (public.is_admin());
create policy emp_delete on public.employees for delete to authenticated
  using (public.is_admin());
create policy emp_update on public.employees for update to authenticated
  using  (public.is_admin() or lower(email) = lower(auth.jwt() ->> 'email'))
  with check (public.is_admin() or (lower(email) = lower(auth.jwt() ->> 'email') and role = 'member'));

-- CLIENTS / TASKS / SHIFTS: admin-only writes
drop policy if exists cli_write   on public.clients;
drop policy if exists task_write  on public.tasks;
drop policy if exists shift_write on public.shifts;
create policy cli_write   on public.clients for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy task_write  on public.tasks   for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy shift_write on public.shifts  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- LOGS: members clock in/out their own; admins manage all
drop policy if exists log_insert on public.logs;
drop policy if exists log_update on public.logs;
drop policy if exists log_delete on public.logs;
create policy log_insert on public.logs for insert to authenticated
  with check (public.is_admin() or employee_id = public.my_employee_id());
create policy log_update on public.logs for update to authenticated
  using  (public.is_admin() or employee_id = public.my_employee_id())
  with check (public.is_admin() or employee_id = public.my_employee_id());
create policy log_delete on public.logs for delete to authenticated
  using (public.is_admin());

-- 5. Members can change ONLY a task's status — via this function -----------
--    (table-level task writes stay admin-only above; this updates just status)
create or replace function public.set_task_status(p_task uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_team_member() then raise exception 'Not authorized'; end if;
  if p_status not in ('Not Started','In Progress','Review','Completed') then
    raise exception 'Invalid status';
  end if;
  update public.tasks set status = p_status where id = p_task;
end;
$$;
grant execute on function public.set_task_status(uuid, text) to authenticated;
