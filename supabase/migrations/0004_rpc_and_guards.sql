-- ============================================================
-- Migration 0004 — RPC, audit triggers, guard voucher, DBA reconcile
-- Prasyarat : 0003_seed.sql
-- Lanjutan  : 0005_security_tests.sql
-- STATUS    : Belum dieksekusi, belum diuji.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. TIMEZONE HELPER
-- ------------------------------------------------------------
create or replace function public.app_timezone()
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select coalesce(
    (select value from public.app_settings where key = 'meal_timezone'),
    'UTC'
  );
$$;
revoke all on function public.app_timezone() from public;
grant execute on function public.app_timezone() to authenticated;

-- ------------------------------------------------------------
-- 2. AUDIT TRIGGERS
-- ------------------------------------------------------------
-- Attendance audit: TG_OP eksplisit
create or replace function public.audit_attendance_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_id uuid;
  v_emp text;
  v_date date;
  v_before jsonb := null;
  v_after  jsonb := null;
begin
  if tg_op = 'INSERT' then
    v_id := new.id; v_emp := new.employee_id; v_date := new.attendance_date;
    v_after := to_jsonb(new);
  elsif tg_op = 'UPDATE' then
    v_id := new.id; v_emp := new.employee_id; v_date := new.attendance_date;
    v_before := to_jsonb(old); v_after := to_jsonb(new);
  elsif tg_op = 'DELETE' then
    v_id := old.id; v_emp := old.employee_id; v_date := old.attendance_date;
    v_before := to_jsonb(old);
  else
    raise exception 'TG_OP tidak dikenal: %', tg_op;
  end if;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'attendance.' || lower(tg_op),
    'attendance',
    v_id::text,
    jsonb_build_object(
      'employee_id', v_emp,
      'attendance_date', v_date,
      'before', v_before,
      'after',  v_after
    )
  );
  return coalesce(new, old);
end;
$$;
revoke all on function public.audit_attendance_change() from public;

drop trigger if exists trg_attendance_audit on public.attendance;
create trigger trg_attendance_audit
  after insert or update or delete on public.attendance
  for each row execute function public.audit_attendance_change();

-- Config audit (meal_schedules + meal_eligibility)
create or replace function public.audit_config_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_id text;
begin
  if tg_op = 'INSERT' then
    v_id := (to_jsonb(new)->>'id');
  elsif tg_op = 'UPDATE' then
    v_id := (to_jsonb(new)->>'id');
  elsif tg_op = 'DELETE' then
    v_id := (to_jsonb(old)->>'id');
  else
    raise exception 'TG_OP tidak dikenal: %', tg_op;
  end if;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    tg_table_name || '.' || lower(tg_op),
    tg_table_name,
    coalesce(v_id, 'unknown'),
    jsonb_build_object(
      'before', case when tg_op = 'INSERT' then null else to_jsonb(old) end,
      'after',  case when tg_op = 'DELETE' then null else to_jsonb(new) end
    )
  );
  return coalesce(new, old);
end;
$$;
revoke all on function public.audit_config_change() from public;

drop trigger if exists trg_schedules_audit on public.meal_schedules;
create trigger trg_schedules_audit
  after insert or update or delete on public.meal_schedules
  for each row execute function public.audit_config_change();

drop trigger if exists trg_eligibility_audit on public.meal_eligibility;
create trigger trg_eligibility_audit
  after insert or update or delete on public.meal_eligibility
  for each row execute function public.audit_config_change();

-- ------------------------------------------------------------
-- 3. GUARD VOUCHER IMMUTABILITY
-- ------------------------------------------------------------
create or replace function public.guard_voucher_update()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.id               is distinct from old.id               then
    raise exception 'voucher.id immutable' using errcode = '42501';
  end if;
  if new.voucher_no       is distinct from old.voucher_no       then
    raise exception 'voucher_no immutable' using errcode = '42501';
  end if;
  if new.employee_id      is distinct from old.employee_id      then
    raise exception 'employee_id immutable' using errcode = '42501';
  end if;
  if new.meal_schedule_id is distinct from old.meal_schedule_id then
    raise exception 'meal_schedule_id immutable' using errcode = '42501';
  end if;
  if new.voucher_date     is distinct from old.voucher_date     then
    raise exception 'voucher_date immutable' using errcode = '42501';
  end if;
  if new.issued_at        is distinct from old.issued_at        then
    raise exception 'issued_at immutable' using errcode = '42501';
  end if;
  if (new.issued_by is null) <> (old.issued_by is null) then
    raise exception 'issued_by immutable' using errcode = '42501';
  elsif new.issued_by is distinct from old.issued_by then
    raise exception 'issued_by immutable' using errcode = '42501';
  end if;
  if (new.device_id is null) <> (old.device_id is null) then
    raise exception 'device_id immutable' using errcode = '42501';
  elsif new.device_id is distinct from old.device_id then
    raise exception 'device_id immutable' using errcode = '42501';
  end if;

  if new.status is distinct from old.status then
    if not (old.status = 'issued' and new.status in ('redeemed','cancelled')) then
      raise exception 'Transisi status tidak sah: % -> %', old.status, new.status
        using errcode = '22000';
    end if;
  end if;

  return new;
end;
$$;
revoke all on function public.guard_voucher_update() from public;

drop trigger if exists trg_vouchers_immutable on public.vouchers;
create trigger trg_vouchers_immutable
  before update on public.vouchers
  for each row execute function public.guard_voucher_update();

-- ------------------------------------------------------------
-- 4. RPC issue_voucher
-- ------------------------------------------------------------
create or replace function public.issue_voucher(
  p_employee_id text,
  p_meal_schedule_id uuid,
  p_voucher_date date,
  p_device_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_tz text := public.app_timezone();
  v_now_local timestamp := now() at time zone v_tz;
  v_today date := (now() at time zone v_tz)::date;
  v_now_time time := v_now_local::time;
  v_end_plus_grace time;
  v_emp record;
  v_sched record;
  v_att record;
  v_rule record;
  v_existing record;
  v_voucher public.vouchers%rowtype;
  v_eligible boolean := false;
  v_new_no text;
begin
  if not public.is_active_operator_or_admin() then
    return jsonb_build_object('ok', false, 'code', 'UNAUTHORIZED');
  end if;

  select * into v_sched from public.meal_schedules
    where id = p_meal_schedule_id and is_active = true;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'SCHEDULE_NOT_FOUND');
  end if;

  if v_sched.start_time >= v_sched.end_time then
    return jsonb_build_object('ok', false, 'code', 'OVERNIGHT_SLOT_UNSUPPORTED');
  end if;

  -- grace 60m, dibatasi 23:59:59
  if v_sched.end_time >= time '23:00' then
    v_end_plus_grace := time '23:59:59';
  else
    v_end_plus_grace := v_sched.end_time + interval '60 minutes';
  end if;
  if v_end_plus_grace < v_sched.end_time then
    v_end_plus_grace := time '23:59:59';
  end if;

  if p_voucher_date <> v_today then
    return jsonb_build_object('ok', false, 'code', 'INVALID_DATE',
      'timezone', v_tz);
  end if;

  if v_now_time < v_sched.start_time or v_now_time > v_end_plus_grace then
    return jsonb_build_object('ok', false, 'code', 'OUTSIDE_WINDOW',
      'timezone', v_tz, 'now_time', v_now_time,
      'window_end', v_end_plus_grace);
  end if;

  select * into v_emp from public.employees
    where employee_id = p_employee_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'EMPLOYEE_NOT_FOUND');
  end if;
  if v_emp.employment_status not in ('active','contract') then
    return jsonb_build_object('ok', false, 'code', 'EMPLOYEE_INACTIVE');
  end if;

  select * into v_att from public.attendance
    where employee_id = v_emp.employee_id
      and attendance_date = p_voucher_date;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'ATTENDANCE_NOT_FOUND');
  end if;

  select * into v_rule from public.meal_eligibility
    where meal_schedule_id = p_meal_schedule_id
      and is_active = true
      and (applicable_department is null or applicable_department = v_emp.department)
      and (applicable_shift is null or applicable_shift = v_emp.shift)
      and (applicable_status is null or applicable_status = v_emp.employment_status)
      and (v_att.attendance_status = any(required_attendance_statuses))
    order by priority asc
    limit 1;
  if found then
    v_eligible := true;
  end if;
  if not v_eligible then
    return jsonb_build_object('ok', false, 'code', 'NOT_ELIGIBLE');
  end if;

  select * into v_existing from public.vouchers
    where employee_id = v_emp.employee_id
      and meal_schedule_id = p_meal_schedule_id
      and voucher_date = p_voucher_date
      and status <> 'cancelled';
  if found then
    return jsonb_build_object('ok', false, 'code', 'DUPLICATE',
      'existing_voucher_no', v_existing.voucher_no);
  end if;

  v_new_no := 'CVS-' || to_char(p_voucher_date, 'YYYYMMDD') || '-' ||
              to_char(v_now_local, 'HH24MISS') || '-' ||
              upper(substr(encode(extensions.gen_random_bytes(4), 'hex'), 1, 6));

  begin
    insert into public.vouchers (
      voucher_no, employee_id, meal_schedule_id, voucher_date,
      status, issued_at, issued_by, device_id
    ) values (
      v_new_no, v_emp.employee_id, p_meal_schedule_id, p_voucher_date,
      'issued', now(), auth.uid(), p_device_id
    ) returning * into v_voucher;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'code', 'DUPLICATE',
      'message', 'Concurrent duplicate detected.');
  end;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(), 'voucher.issue', 'voucher', v_voucher.id::text,
    jsonb_build_object(
      'voucher_no', v_voucher.voucher_no,
      'employee_id', v_emp.employee_id,
      'meal_schedule_id', p_meal_schedule_id,
      'voucher_date', p_voucher_date,
      'device_id', p_device_id,
      'device_id_is_hint_only', true,
      'timezone', v_tz
    )
  );

  return jsonb_build_object(
    'ok', true,
    'voucher', jsonb_build_object(
      'id', v_voucher.id,
      'voucher_no', v_voucher.voucher_no,
      'employee_id', v_emp.employee_id,
      'full_name', v_emp.full_name,
      'department', v_emp.department,
      'meal_name', v_sched.name,
      'voucher_date', v_voucher.voucher_date,
      'issued_at', v_voucher.issued_at
    )
  );
end;
$$;
revoke all on function public.issue_voucher(text, uuid, date, text) from public;
revoke all on function public.issue_voucher(text, uuid, date, text) from anon;
grant  execute on function public.issue_voucher(text, uuid, date, text) to authenticated;

-- ------------------------------------------------------------
-- 5. RPC redeem / cancel
-- ------------------------------------------------------------
create or replace function public.redeem_voucher(p_voucher_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_row public.vouchers%rowtype;
begin
  if not public.is_active_operator_or_admin() then
    return jsonb_build_object('ok', false, 'code', 'UNAUTHORIZED');
  end if;

  select * into v_row from public.vouchers where id = p_voucher_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND');
  end if;
  if v_row.status <> 'issued' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STATE',
      'current_status', v_row.status);
  end if;

  update public.vouchers
     set status = 'redeemed', redeemed_at = now()
   where id = p_voucher_id;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(), 'voucher.redeem', 'voucher', p_voucher_id::text,
    jsonb_build_object('voucher_no', v_row.voucher_no,
                       'employee_id', v_row.employee_id)
  );

  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.redeem_voucher(uuid) from public;
revoke all on function public.redeem_voucher(uuid) from anon;
grant  execute on function public.redeem_voucher(uuid) to authenticated;

create or replace function public.cancel_voucher(p_voucher_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_row public.vouchers%rowtype;
begin
  if not public.is_active_operator_or_admin() then
    return jsonb_build_object('ok', false, 'code', 'UNAUTHORIZED');
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 then
    return jsonb_build_object('ok', false, 'code', 'REASON_REQUIRED');
  end if;

  select * into v_row from public.vouchers where id = p_voucher_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'NOT_FOUND');
  end if;
  if v_row.status <> 'issued' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_STATE',
      'current_status', v_row.status);
  end if;

  update public.vouchers
     set status = 'cancelled',
         cancelled_at = now(),
         cancel_reason = p_reason
   where id = p_voucher_id;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(), 'voucher.cancel', 'voucher', p_voucher_id::text,
    jsonb_build_object('voucher_no', v_row.voucher_no,
                       'employee_id', v_row.employee_id,
                       'reason', p_reason)
  );

  return jsonb_build_object('ok', true);
end;
$$;
revoke all on function public.cancel_voucher(uuid, text) from public;
revoke all on function public.cancel_voucher(uuid, text) from anon;
grant  execute on function public.cancel_voucher(uuid, text) to authenticated;

-- ------------------------------------------------------------
-- 6. DBA RECONCILE ADMINS (owner-only)
-- ------------------------------------------------------------
create or replace function public.dba_reconcile_admins()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_allow_count int;
  v_demoted int := 0;
  v_detail jsonb := '[]'::jsonb;
begin
  if session_user not in ('postgres','supabase_admin') then
    raise exception 'dba_reconcile_admins hanya boleh dijalankan oleh DBA'
      using errcode = '42501';
  end if;

  select count(*) into v_allow_count from public.admin_reconciliation;
  if v_allow_count = 0 then
    raise exception 'admin_reconciliation kosong: isi allowlist dulu'
      using errcode = 'P0001';
  end if;

  insert into public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  select null, 'admin.reconcile.demote', 'profile', p.id::text,
    jsonb_build_object(
      'email', p.email, 'old_role', p.role,
      'reason', 'not_in_allowlist', 'executed_by', session_user
    )
  from public.profiles p
  where p.role = 'admin'
    and not exists (
      select 1 from public.admin_reconciliation ar
      where lower(ar.email) = lower(p.email)
    );

  with demoted as (
    update public.profiles p
       set role = 'operator'
     where p.role = 'admin'
       and not exists (
         select 1 from public.admin_reconciliation ar
         where lower(ar.email) = lower(p.email)
       )
    returning p.email
  )
  select coalesce(jsonb_agg(email), '[]'::jsonb), count(*)
    into v_detail, v_demoted
    from demoted;

  return jsonb_build_object(
    'ok', true,
    'allowlist_count', v_allow_count,
    'demoted_count', v_demoted,
    'demoted_emails', v_detail
  );
end;
$$;
revoke all on function public.dba_reconcile_admins() from public;
revoke all on function public.dba_reconcile_admins() from anon;
revoke all on function public.dba_reconcile_admins() from authenticated;

-- ------------------------------------------------------------
-- 7. GUARD app_settings (hanya DBA lewat SQL Editor)
-- ------------------------------------------------------------
revoke insert, update, delete on table public.app_settings from anon, authenticated;
revoke insert, update, delete on table public.admin_reconciliation from anon, authenticated;

commit;