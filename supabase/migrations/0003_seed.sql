-- ============================================================
-- Migration 0003 — Seed default data
-- Prasyarat : 0002_rls_policies.sql
-- Lanjutan  : 0004_rpc_and_guards.sql
-- STATUS    : Belum dieksekusi, belum diuji.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. APP SETTINGS
-- ------------------------------------------------------------
insert into public.app_settings (key, value)
values ('meal_timezone', 'Asia/Jakarta')
on conflict (key) do nothing;

-- ------------------------------------------------------------
-- 2. MEAL SCHEDULES
-- ------------------------------------------------------------
insert into public.meal_schedules (code, name, start_time, end_time, is_active)
values
  ('breakfast', 'Sarapan',      time '06:00', time '08:00', true),
  ('lunch',     'Makan Siang',  time '11:00', time '14:00', true),
  ('dinner',    'Makan Malam',  time '17:00', time '20:00', true)
on conflict (code) do nothing;

-- ------------------------------------------------------------
-- 3. MEAL ELIGIBILITY DEFAULT (1 rule per schedule)
-- ------------------------------------------------------------
insert into public.meal_eligibility (
  name, meal_schedule_id, required_attendance_statuses, priority, is_active
)
select
  'Default: hadir untuk ' || ms.name,
  ms.id,
  array['present','late']::text[],
  100,
  true
from public.meal_schedules ms
where not exists (
  select 1 from public.meal_eligibility me where me.meal_schedule_id = ms.id
);

commit;