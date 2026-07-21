-- ============================================================
--  Milestone by Zeus — v6: open task authoring + detail fields
--  Run ONCE, after supabase-v5-taskid.sql. Safe to re-run.
--
--  1. Any team member (not just admins) can now CREATE and EDIT tasks.
--     Deleting a task stays admin-only.
--  2. New free-text fields on a task: description, business value,
--     acceptance criteria, comments.
-- ============================================================

-- 1. New detail fields -----------------------------------------------------
alter table public.tasks add column if not exists description         text;
alter table public.tasks add column if not exists business_value      text;
alter table public.tasks add column if not exists acceptance_criteria text;
alter table public.tasks add column if not exists comments            text;

-- 2. Permissions: replace the admin-only write rule with granular ones ------
drop policy if exists task_write  on public.tasks;
drop policy if exists task_insert on public.tasks;
drop policy if exists task_update on public.tasks;
drop policy if exists task_delete on public.tasks;

-- create + edit: anyone on the roster
create policy task_insert on public.tasks for insert to authenticated
  with check (public.is_team_member());
create policy task_update on public.tasks for update to authenticated
  using (public.is_team_member()) with check (public.is_team_member());

-- delete: admins only (destructive, kept restricted)
create policy task_delete on public.tasks for delete to authenticated
  using (public.is_admin());
