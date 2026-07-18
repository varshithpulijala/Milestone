-- ============================================================
--  Zeus AI Hub — v3: reporting managers & project leads
--  Run ONCE, after supabase-tasks-v2.sql. Safe to re-run.
--
--  Adds:
--    employees.manager_id  → each employee's reporting manager
--    projects.manager_id   → the project manager
--    projects.checker_id   → the project's checker
--
--  No data is deleted. Existing policies already cover these columns
--  (admins manage employees & projects), so nothing else changes.
-- ============================================================

alter table public.employees
  add column if not exists manager_id uuid references public.employees(id) on delete set null;

alter table public.projects
  add column if not exists manager_id uuid references public.employees(id) on delete set null;

alter table public.projects
  add column if not exists checker_id uuid references public.employees(id) on delete set null;
