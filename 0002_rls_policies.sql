-- ============================================================
-- Migration 0002 — RLS, helper role, trigger user, guard profile
-- Prasyarat : 0001_init_schema.sql
-- Lanjutan  : 0003_seed.sql
-- STATUS    : Belum dieksekusi, belum diuji.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. HELPER FUNCTIONS (SECURITY DEFINER + search_path aman)
-- ------------------------------------------------------------
-- is_admin(): true jika auth.uid() milik admin aktif.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and is_active = true
  );
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('admin','operator')
      and is_active = true
  );
$$;
revoke all on function public.is_staff() from public;
grant execute on function public.is_staff() to authenticated;

create or replace function public.is_active_operator_or_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('admin','operator')
      and is_active = true
  );
$$;
revoke all on function public.is_active_operator_or_admin() from public;
grant execute on function public.is_active_operator_or_admin() to authenticated;

-- ------------------------------------------------------------
-- 2. AUTO-CREATE PROFILE SAAT SIGNUP
--    Role SELALU 'operator'. Tidak pernah dari raw_user_meta_data.
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.profiles (id, email, full_name, role, is_active)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    'operator',
    true
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function public.handle_new_user() from public;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------
-- 3. GUARD KOLOM SENSITIF PROFILES
--    Non-admin tidak boleh ubah role / is_active / email / profil orang lain.
-- ------------------------------------------------------------
create or replace function public.guard_profile_privilege_columns()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if public.is_admin() then
    return new;
  end if;

  if new.role is distinct from old.role then
    raise exception 'Tidak diizinkan mengubah role' using errcode = '42501';
  end if;
  if new.is_active is distinct from old.is_active then
    raise exception 'Tidak diizinkan mengubah is_active' using errcode = '42501';
  end if;
  if new.email is distinct from old.email then
    raise exception 'Email hanya dapat diubah via Supabase Auth' using errcode = '42501';
  end if;
  if auth.uid() is null or auth.uid() <> old.id then
    raise exception 'Tidak diizinkan mengubah profil pengguna lain' using errcode = '42501';
  end if;

  return new;
end;
$$;
revoke all on function public.guard_profile_privilege_columns() from public;

drop trigger if exists trg_profiles_guard on public.profiles;
create trigger trg_profiles_guard
  before update on public.profiles
  for each row execute function public.guard_profile_privilege_columns();

-- ------------------------------------------------------------
-- 4. RLS POLICIES
-- ------------------------------------------------------------
alter table public.profiles             enable row level security;
alter table public.employees            enable row level security;
alter table public.meal_schedules       enable row level security;
alter table public.attendance           enable row level security;
alter table public.meal_eligibility     enable row level security;
alter table public.vouchers             enable row level security;
alter table public.audit_logs           enable row level security;
alter table public.app_settings         enable row level security;
alter table public.admin_reconciliation enable row level security;

-- PROFILES
drop policy if exists profiles_self_select on public.profiles;
create policy profiles_self_select on public.profiles
  for select using (auth.uid() = id or public.is_admin());

drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update on public.profiles
  for update using (auth.uid() = id or public.is_admin())
  with check (auth.uid() = id or public.is_admin());

drop policy if exists profiles_admin_all on public.profiles;
create policy profiles_admin_all on public.profiles
  for all using (public.is_admin()) with check (public.is_admin());

-- EMPLOYEES
drop policy if exists employees_read on public.employees;
create policy employees_read on public.employees
  for select using (public.is_staff());

drop policy if exists employees_admin_write on public.employees;
create policy employees_admin_write on public.employees
  for all using (public.is_admin()) with check (public.is_admin());

-- MEAL SCHEDULES
drop policy if exists schedules_read on public.meal_schedules;
create policy schedules_read on public.meal_schedules
  for select using (public.is_staff());

drop policy if exists schedules_admin_write on public.meal_schedules;
create policy schedules_admin_write on public.meal_schedules
  for all using (public.is_admin()) with check (public.is_admin());

-- ATTENDANCE
drop policy if exists attendance_read on public.attendance;
create policy attendance_read on public.attendance
  for select using (public.is_staff());

drop policy if exists attendance_insert on public.attendance;
create policy attendance_insert on public.attendance
  for insert with check (public.is_staff());

-- update/delete hanya admin (operator tidak boleh ubah status setelah tercatat)
drop policy if exists attendance_update on public.attendance;
create policy attendance_update on public.attendance
  for update using (public.is_admin()) with check (public.is_admin());

drop policy if exists attendance_delete on public.attendance;
create policy attendance_delete on public.attendance
  for delete using (public.is_admin());

-- MEAL ELIGIBILITY
drop policy if exists eligibility_read on public.meal_eligibility;
create policy eligibility_read on public.meal_eligibility
  for select using (public.is_staff());

drop policy if exists eligibility_admin_write on public.meal_eligibility;
create policy eligibility_admin_write on public.meal_eligibility
  for all using (public.is_admin()) with check (public.is_admin());

-- VOUCHERS: read staff, write via RPC saja
drop policy if exists vouchers_read on public.vouchers;
create policy vouchers_read on public.vouchers
  for select using (public.is_staff());

-- (Tidak ada INSERT/UPDATE/DELETE policy. Semua via RPC di 0004.)

-- AUDIT LOGS: read admin, insert via SECURITY DEFINER saja
drop policy if exists audit_read on public.audit_logs;
create policy audit_read on public.audit_logs
  for select using (public.is_admin());

-- APP SETTINGS & ADMIN RECONCILIATION: lock total
-- Tidak ada policy SELECT/INSERT/UPDATE/DELETE untuk client.
revoke all on table public.app_settings         from anon, authenticated;
revoke all on table public.admin_reconciliation from anon, authenticated;

commit;