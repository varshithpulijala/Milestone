-- ============================================================
--  Zeus AI Hub — v4: task activity log + hour totals
--  Run ONCE, after supabase-v3-managers.sql. Safe to re-run.
--
--  1. task_activity  — an audit trail of every task change (who / what /
--     when). Written by a database trigger, so it captures changes from
--     the UI, the member status function, and bulk imports alike. Nobody
--     can forge or edit entries; the app can only read them.
--  2. employee_hours() — totals hours worked server-side, so the app
--     doesn't have to download every clock record to add them up.
-- ============================================================

-- 1. ACTIVITY TABLE --------------------------------------------------------
-- task_id is deliberately NOT a foreign key: history must survive the
-- deletion of the task it describes.
create table if not exists public.task_activity (
  id          uuid primary key default gen_random_uuid(),
  task_id     uuid,
  project_id  uuid,
  actor_id    uuid references public.employees(id) on delete set null,
  actor_email text,
  action      text not null,          -- 'created' | 'updated' | 'deleted'
  changes     jsonb not null default '[]'::jsonb,   -- [{field, from, to}]
  task_label  text,                   -- snapshot of the task name, for readability
  created_at  timestamptz default now()
);

create index if not exists task_activity_task_idx    on public.task_activity(task_id);
create index if not exists task_activity_created_idx on public.task_activity(created_at desc);

-- 2. TRIGGER ---------------------------------------------------------------
create or replace function public.log_task_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_changes jsonb := '[]'::jsonb;
  v_action  text;
  v_task    uuid;
  v_project uuid;
  v_label   text;
  v_from    text;
  v_to      text;
begin
  if TG_OP = 'INSERT' then
    v_action := 'created'; v_task := NEW.id; v_project := NEW.project_id; v_label := NEW.detailed_task;

  elsif TG_OP = 'DELETE' then
    v_action := 'deleted'; v_task := OLD.id; v_project := OLD.project_id; v_label := OLD.detailed_task;

  else
    v_action := 'updated'; v_task := NEW.id; v_project := NEW.project_id; v_label := NEW.detailed_task;

    if NEW.status is distinct from OLD.status then
      v_changes := v_changes || jsonb_build_array(jsonb_build_object('field','Status','from',OLD.status,'to',NEW.status));
    end if;
    if NEW.detailed_task is distinct from OLD.detailed_task then
      v_changes := v_changes || jsonb_build_array(jsonb_build_object('field','Detailed Task','from',OLD.detailed_task,'to',NEW.detailed_task));
    end if;
    if NEW.primary_task is distinct from OLD.primary_task then
      v_changes := v_changes || jsonb_build_array(jsonb_build_object('field','Primary Task','from',OLD.primary_task,'to',NEW.primary_task));
    end if;
    if NEW.sub_task is distinct from OLD.sub_task then
      v_changes := v_changes || jsonb_build_array(jsonb_build_object('field','Sub task','from',OLD.sub_task,'to',NEW.sub_task));
    end if;
    if NEW.developer_id is distinct from OLD.developer_id then
      v_from := coalesce((select name from public.employees where id = OLD.developer_id), 'Unassigned');
      v_to   := coalesce((select name from public.employees where id = NEW.developer_id), 'Unassigned');
      v_changes := v_changes || jsonb_build_array(jsonb_build_object('field','Developer','from',v_from,'to',v_to));
    end if;
    if NEW.checker_id is distinct from OLD.checker_id then
      v_from := coalesce((select name from public.employees where id = OLD.checker_id), 'Unassigned');
      v_to   := coalesce((select name from public.employees where id = NEW.checker_id), 'Unassigned');
      v_changes := v_changes || jsonb_build_array(jsonb_build_object('field','Checker','from',v_from,'to',v_to));
    end if;
    if NEW.start_date is distinct from OLD.start_date then
      v_changes := v_changes || jsonb_build_array(jsonb_build_object('field','Start date','from',OLD.start_date::text,'to',NEW.start_date::text));
    end if;
    if NEW.end_date is distinct from OLD.end_date then
      v_changes := v_changes || jsonb_build_array(jsonb_build_object('field','End date','from',OLD.end_date::text,'to',NEW.end_date::text));
    end if;
    if NEW.project_id is distinct from OLD.project_id then
      v_changes := v_changes || jsonb_build_array(jsonb_build_object('field','Project','from',
        coalesce((select name from public.projects where id = OLD.project_id),'—'),'to',
        coalesce((select name from public.projects where id = NEW.project_id),'—')));
    end if;

    -- nothing meaningful changed (e.g. a no-op save): don't record noise
    if v_changes = '[]'::jsonb then return NEW; end if;
  end if;

  insert into public.task_activity (task_id, project_id, actor_id, actor_email, action, changes, task_label)
  values (v_task, v_project, public.my_employee_id(), auth.jwt() ->> 'email', v_action, v_changes, v_label);

  if TG_OP = 'DELETE' then return OLD; end if;
  return NEW;
end;
$$;

drop trigger if exists trg_task_activity on public.tasks;
create trigger trg_task_activity
  after insert or update or delete on public.tasks
  for each row execute function public.log_task_activity();

-- 3. RLS — the team can read history; only the trigger can write it -------
alter table public.task_activity enable row level security;
drop policy if exists read_all on public.task_activity;
create policy read_all on public.task_activity
  for select to authenticated using (public.is_team_member());
-- (no insert/update/delete policies on purpose: entries are immutable)

-- 4. Hour totals computed server-side --------------------------------------
-- Lets the app show accurate totals without downloading every clock record.
create or replace function public.employee_hours(p_since timestamptz default null)
returns table (employee_id uuid, hours numeric)
language sql security definer set search_path = public as $$
  select l.employee_id,
         round(sum(extract(epoch from (coalesce(l.clock_out, now()) - l.clock_in)) / 3600.0)::numeric, 2)
  from public.logs l
  where public.is_team_member()
    and (p_since is null or l.clock_in >= p_since)
  group by l.employee_id;
$$;
grant execute on function public.employee_hours(timestamptz) to authenticated;
