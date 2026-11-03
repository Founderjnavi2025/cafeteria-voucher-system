-- ============================================================
-- CAFETERIA VOUCHER SYSTEM (CVS)
-- Migration 0001 — Initial Schema
-- ============================================================
-- Fase       : 1 — Fondasi DB
-- PR         : PR-02
-- Baseline   : DOCS/BASELINE.md v1.0, §7 Rancangan Database
-- Prasyarat  : Tidak ada
-- Lanjutan   : 0002_rls_policies.sql
--
-- CAKUPAN FILE INI:
--   * Tabel inti sesuai §7.
--   * Foreign key, unique constraint, check constraint.
--   * Index dasar (lookup & filter).
--   * Trigger updated_at murni struktural.
--   * Extension yang dibutuhkan.
--
-- DI LUAR CAKUPAN (dikerjakan di migration berikutnya):
--   * Row Level Security (RLS) & policy  -> 0002 / 0004 / 0005 / 0006
--   * SECURITY DEFINER + search_path aman -> 0004 / 0005 / 0006
--   * Guard trigger kolom sensitif        -> 0004 / 0005
--   * Audit trigger                       -> 0005 / 0006
--   * RPC issue/redeem/cancel voucher     -> 0005 / 0006
--   * Rekonsiliasi admin                  -> 0005 / 0006
--   * Seed data (meal_schedules, dll.)    -> 0003
--
-- STATUS: RANCANGAN. BELUM DIEKSEKUSI. BELUM DIUJI.
-- ============================================================

-- ------------------------------------------------------------
-- 0. EXTENSIONS
-- ------------------------------------------------------------
-- pgcrypto: dibutuhkan untuk gen_random_uuid() (default PK) dan
--           gen_random_bytes() (dipakai RPC voucher di migration 0005).
-- Di Supabase, extension biasanya dipasang di schema `extensions`.
-- Migration 0005 akan memanggilnya dengan prefix `extensions.`.
-- ------------------------------------------------------------
create extension if not exists "pgcrypto" with schema extensions;

-- ------------------------------------------------------------
-- 1. HELPER: TRIGGER updated_at (STRUKTURAL SAJA)
-- ------------------------------------------------------------
-- Catatan: ini HANYA set updated_at = now(). Tidak ada logika otorisasi.
-- SECURITY DEFINER + search_path aman akan ditambahkan di 0004/0005.
-- ------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ------------------------------------------------------------
-- 2. TABEL: profiles
-- ------------------------------------------------------------
-- Profil pengguna aplikasi (admin / operator / viewer).
-- Baris dibuat otomatis saat user signup via trigger di migration 0002/0004.
-- Migration ini hanya membuat struktur; trigger auto-create BELUM ada.
-- ------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid        primary key references auth.users(id) on delete cascade,
  email       text        not null unique,
  full_name   text,
  role        text        not null default 'operator'
                          check (role in ('admin','operator','viewer')),
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists idx_profiles_role
  on public.profiles(role);

create index if not exists idx_profiles_is_active
  on public.profiles(is_active);

drop trigger if exists trg_profiles_updated on public.profiles;
create trigger trg_profiles_updated
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 3. TABEL: employees
-- ------------------------------------------------------------
-- Master data karyawan.
-- employee_id = ID bisnis (bukan PK). Dirujuk oleh attendance & vouchers.
-- ------------------------------------------------------------
create table if not exists public.employees (
  id                 uuid        primary key default extensions.gen_random_uuid(),
  employee_id        text        not null unique,
  full_name          text        not null,
  department         text,
  position           text,
  shift              text        not null default 'day'
                                 check (shift in ('day','night','morning','evening','off')),
  employment_status  text        not null default 'active'
                                 check (employment_status in ('active','inactive','contract','resigned')),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index if not exists idx_employees_employee_id
  on public.employees(employee_id);

create index if not exists idx_employees_status
  on public.employees(employment_status);

create index if not exists idx_employees_department
  on public.employees(department);

drop trigger if exists trg_employees_updated on public.employees;
create trigger trg_employees_updated
  before update on public.employees
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 4. TABEL: meal_schedules
-- ------------------------------------------------------------
-- Slot makan yang dapat dikonfigurasi admin.
-- Aturan start_time < end_time ditegakkan via check constraint
-- (slot lintas tengah malam ditolak sesuai baseline §2.1 B9).
-- ------------------------------------------------------------
create table if not exists public.meal_schedules (
  id          uuid        primary key default extensions.gen_random_uuid(),
  code        text        not null unique,
  name        text        not null,
  start_time  time        not null,
  end_time    time        not null,
  is_active   boolean     not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint chk_meal_schedules_time_order
    check (start_time < end_time)
);

create index if not exists idx_meal_schedules_active
  on public.meal_schedules(is_active);

drop trigger if exists trg_meal_schedules_updated on public.meal_schedules;
create trigger trg_meal_schedules_updated
  before update on public.meal_schedules
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 5. TABEL: attendance
-- ------------------------------------------------------------
-- Data kehadiran karyawan (input manual / CSV pada MVP).
-- Unique (employee_id, attendance_date) => satu baris per karyawan per hari.
-- FK ke employees.employee_id (bukan ke employees.id) sesuai baseline §7.1.
-- ------------------------------------------------------------
create table if not exists public.attendance (
  id                 uuid        primary key default extensions.gen_random_uuid(),
  employee_id        text        not null
                                 references public.employees(employee_id)
                                 on update cascade
                                 on delete cascade,
  attendance_date    date        not null,
  check_in           time,
  check_out          time,
  attendance_status  text        not null default 'present'
                                 check (attendance_status in
                                   ('present','late','absent','leave','sick','holiday')),
  shift              text,
  notes              text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint uq_attendance_employee_date
    unique (employee_id, attendance_date)
);

create index if not exists idx_attendance_date
  on public.attendance(attendance_date);

create index if not exists idx_attendance_employee
  on public.attendance(employee_id);

drop trigger if exists trg_attendance_updated on public.attendance;
create trigger trg_attendance_updated
  before update on public.attendance
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 6. TABEL: meal_eligibility
-- ------------------------------------------------------------
-- Aturan kelayakan makan (dapat dikonfigurasi admin).
-- NULL pada applicable_* = berlaku untuk semua.
-- required_attendance_statuses = array status absensi yang memenuhi syarat.
-- ------------------------------------------------------------
create table if not exists public.meal_eligibility (
  id                          uuid        primary key default extensions.gen_random_uuid(),
  name                        text        not null,
  meal_schedule_id            uuid        not null
                                          references public.meal_schedules(id)
                                          on update cascade
                                          on delete cascade,
  applicable_department       text,
  applicable_shift            text,
  applicable_status           text,
  required_attendance_statuses text[]     not null
                                          default array['present','late']::text[],
  is_active                   boolean     not null default true,
  priority                    int         not null default 100,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  constraint chk_meal_eligibility_priority
    check (priority >= 0)
);

create index if not exists idx_meal_eligibility_active
  on public.meal_eligibility(is_active);

create index if not exists idx_meal_eligibility_schedule
  on public.meal_eligibility(meal_schedule_id);

drop trigger if exists trg_meal_eligibility_updated on public.meal_eligibility;
create trigger trg_meal_eligibility_updated
  before update on public.meal_eligibility
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 7. TABEL: vouchers
-- ------------------------------------------------------------
-- Voucher makan yang diterbitkan.
-- Anti-duplikat: unique partial index (employee_id, meal_schedule_id, voucher_date)
--   WHERE status <> 'cancelled'.
-- Akses langsung (INSERT/UPDATE/DELETE) akan diblok RLS di migration 0002+;
-- penerbitan hanya via RPC di 0004.
-- ------------------------------------------------------------
create table if not exists public.vouchers (
  id                uuid        primary key default extensions.gen_random_uuid(),
  voucher_no        text        not null unique,
  employee_id       text        not null
                                references public.employees(employee_id)
                                on update cascade
                                on delete restrict,
  meal_schedule_id  uuid        not null
                                references public.meal_schedules(id)
                                on update cascade
                                on delete restrict,
  voucher_date      date        not null,
  status            text        not null default 'issued'
                                check (status in ('issued','redeemed','cancelled')),
  issued_at         timestamptz not null default now(),
  issued_by         uuid        references public.profiles(id)
                                on update cascade
                                on delete set null,
  device_id         text,
  redeemed_at       timestamptz,
  cancelled_at      timestamptz,
  cancel_reason     text
);

-- KUNCI ANTI-DUPLIKAT
create unique index if not exists uq_vouchers_employee_meal_date
  on public.vouchers(employee_id, meal_schedule_id, voucher_date)
  where status <> 'cancelled';

create index if not exists idx_vouchers_no
  on public.vouchers(voucher_no);

create index if not exists idx_vouchers_date
  on public.vouchers(voucher_date);

create index if not exists idx_vouchers_status
  on public.vouchers(status);

create index if not exists idx_vouchers_employee
  on public.vouchers(employee_id);

-- ------------------------------------------------------------
-- 8. TABEL: audit_logs
-- ------------------------------------------------------------
-- Jejak audit aktivitas.
-- Tidak ada FK ke entity_type/entity_id (generik).
-- actor_id nullable (untuk operasi sistem/DBA yang tidak punya auth.uid()).
-- ------------------------------------------------------------
create table if not exists public.audit_logs (
  id           uuid        primary key default extensions.gen_random_uuid(),
  actor_id     uuid        references public.profiles(id)
                           on update cascade
                           on delete set null,
  action       text        not null,
  entity_type  text,
  entity_id    text,
  metadata     jsonb       not null default '{}'::jsonb,
  ip_address   inet,
  user_agent   text,
  created_at   timestamptz not null default now()
);

create index if not exists idx_audit_created
  on public.audit_logs(created_at desc);

create index if not exists idx_audit_action
  on public.audit_logs(action);

create index if not exists idx_audit_entity
  on public.audit_logs(entity_type, entity_id);

-- ------------------------------------------------------------
-- 9. TABEL: app_settings
-- ------------------------------------------------------------
-- Konfigurasi aplikasi (key-value).
-- Seed `meal_timezone = 'Asia/Jakarta'` dilakukan di migration 0003/0004
-- saat RLS & lockdown diterapkan, BUKAN di sini.
-- File ini HANYA membuat struktur.
-- ------------------------------------------------------------
create table if not exists public.app_settings (
  key         text        primary key,
  value       text        not null,
  updated_at  timestamptz not null default now()
);

drop trigger if exists trg_app_settings_updated on public.app_settings;
create trigger trg_app_settings_updated
  before update on public.app_settings
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 10. TABEL: admin_reconciliation
-- ------------------------------------------------------------
-- Allowlist email admin sah untuk prosedur rekonsiliasi (migration 0004).
-- Isi allowlist dilakukan MANUAL oleh DBA saat persiapan akun Supabase.
-- Migration ini HANYA membuat struktur, TIDAK mengisi data.
-- ------------------------------------------------------------
create table if not exists public.admin_reconciliation (
  email       text        primary key,
  note        text,
  created_at  timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 11. KOMENTAR DOKUMENTASI (ringkas)
-- ------------------------------------------------------------
comment on table public.profiles is
  'Profil pengguna. Baris dibuat otomatis saat signup via trigger di migration 0002.';
comment on table public.employees is
  'Master karyawan. employee_id = ID bisnis (bukan PK), dirujuk attendance & vouchers.';
comment on table public.meal_schedules is
  'Slot makan. start_time < end_time wajib (slot lintas tengah malam ditolak).';
comment on table public.attendance is
  'Kehadiran. MVP: input manual / CSV. Integrasi mesin absensi = pekerjaan terpisah.';
comment on table public.meal_eligibility is
  'Aturan kelayakan. NULL pada applicable_* = berlaku untuk semua.';
comment on table public.vouchers is
  'Voucher. Anti-duplikat via unique partial index. Akses langsung diblok RLS.';
comment on table public.audit_logs is
  'Jejak audit. Client tidak boleh INSERT (dikunci di migration 0004).';
comment on table public.app_settings is
  'Konfigurasi. RLS + lockdown diterapkan di migration 0002.';
comment on table public.admin_reconciliation is
  'Allowlist admin sah. Diisi manual DBA. RLS + lockdown diterapkan di migration 0002.';

-- ============================================================
-- END OF MIGRATION 0001
-- ============================================================
-- File ini hanya membuat struktur. Semua aturan keamanan, RPC, seed,
-- dan audit datang di migration berikutnya (0002–0005).
-- ============================================================
