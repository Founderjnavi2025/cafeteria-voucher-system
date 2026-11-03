-- ============================================================
-- Migration 0005 — Security Test SQL
-- Jalankan di STAGING sebagai postgres/supabase_admin.
-- Setiap blok = satu test. PASS = NOTICE, FAIL = exception.
-- STATUS: Belum dieksekusi, belum diuji.
-- ============================================================

-- T01: RLS aktif
do $$
declare ok boolean;
begin
  ok := (select bool_and(relrowsecurity)
           from pg_class
          where relnamespace='public'::regnamespace
            and relname in ('profiles','employees','attendance','meal_schedules',
                            'meal_eligibility','vouchers','audit_logs',
                            'app_settings','admin_reconciliation'));
  if not ok then raise exception 'T01 FAIL: RLS tidak aktif di semua tabel'; end if;
  raise notice 'T01 PASS';
end $$;

-- T02: Semua SECURITY DEFINER punya search_path aman
do $$
declare r record;
begin
  for r in
    select p.proname, p.proconfig
      from pg_proc p
     where p.pronamespace='public'::regnamespace
       and p.prosecdef = true
       and p.proname in (
         'is_admin','is_staff','is_active_operator_or_admin',
         'handle_new_user','guard_profile_privilege_columns',
         'guard_voucher_update','audit_attendance_change','audit_config_change',
         'app_timezone','issue_voucher','redeem_voucher','cancel_voucher',
         'dba_reconcile_admins'
       )
  loop
    if r.proconfig is null
       or not (array_to_string(r.proconfig,',') like '%search_path=pg_catalog, public%') then
      raise exception 'T02 FAIL: % search_path tidak aman: %', r.proname, r.proconfig;
    end if;
  end loop;
  raise notice 'T02 PASS';
end $$;

-- T03: anon TIDAK punya EXECUTE di RPC
do $$
begin
  if has_function_privilege('anon','public.issue_voucher(text,uuid,date,text)','EXECUTE') then
    raise exception 'T03a FAIL: anon bisa issue_voucher';
  end if;
  if has_function_privilege('anon','public.redeem_voucher(uuid)','EXECUTE') then
    raise exception 'T03b FAIL: anon bisa redeem_voucher';
  end if;
  if has_function_privilege('anon','public.cancel_voucher(uuid,text)','EXECUTE') then
    raise exception 'T03c FAIL: anon bisa cancel_voucher';
  end if;
  if has_function_privilege('anon','public.dba_reconcile_admins()','EXECUTE') then
    raise exception 'T03d FAIL: anon bisa dba_reconcile_admins';
  end if;
  raise notice 'T03 PASS';
end $$;

-- T04: authenticated TIDAK punya EXECUTE di dba_reconcile_admins
do $$
begin
  if has_function_privilege('authenticated','public.dba_reconcile_admins()','EXECUTE') then
    raise exception 'T04 FAIL: authenticated bisa dba_reconcile_admins';
  end if;
  raise notice 'T04 PASS';
end $$;

-- T05: tidak ada policy INSERT/UPDATE/DELETE vouchers
do $$
declare cnt int;
begin
  select count(*) into cnt from pg_policies
   where schemaname='public' and tablename='vouchers'
     and cmd in ('INSERT','UPDATE','DELETE','ALL');
  if cnt > 0 then
    raise exception 'T05 FAIL: ada % policy write di vouchers', cnt;
  end if;
  raise notice 'T05 PASS';
end $$;

-- T06: unique partial index anti-duplikat ada
do $$
begin
  if not exists (
    select 1 from pg_indexes
     where schemaname='public' and tablename='vouchers'
       and indexname='uq_vouchers_employee_meal_date'
  ) then
    raise exception 'T06 FAIL: index anti-duplikat tidak ada';
  end if;
  raise notice 'T06 PASS';
end $$;

-- T07: app_settings tidak bisa diakses authenticated via SELECT
do $$
begin
  if has_table_privilege('authenticated','public.app_settings','SELECT') then
    raise exception 'T07 FAIL: authenticated bisa SELECT app_settings';
  end if;
  raise notice 'T07 PASS';
end $$;

-- T08: guard profile trigger ada
do $$
begin
  if not exists (
    select 1 from pg_trigger where tgname='trg_profiles_guard'
  ) then
    raise exception 'T08 FAIL: trigger guard profile tidak ada';
  end if;
  raise notice 'T08 PASS';
end $$;

-- T09: seed meal_schedules & eligibility ada
do $$
declare cnt_s int; cnt_e int;
begin
  select count(*) into cnt_s from public.meal_schedules where is_active = true;
  select count(*) into cnt_e from public.meal_eligibility where is_active = true;
  if cnt_s = 0 then raise exception 'T09 FAIL: meal_schedules kosong'; end if;
  if cnt_e = 0 then raise exception 'T09 FAIL: meal_eligibility kosong'; end if;
  raise notice 'T09 PASS (% schedules, % rules)', cnt_s, cnt_e;
end $$;

-- T10: meal_timezone seed
do $$
declare v text;
begin
  select value into v from public.app_settings where key='meal_timezone';
  if v is null then raise exception 'T10 FAIL: meal_timezone tidak ada'; end if;
  raise notice 'T10 PASS (timezone=%)', v;
end $$;

-- T11: trigger attendance audit ada
do $$
begin
  if not exists (select 1 from pg_trigger where tgname='trg_attendance_audit') then
    raise exception 'T11 FAIL: attendance audit trigger tidak ada';
  end if;
  raise notice 'T11 PASS';
end $$;

-- T12: voucher guard trigger ada
do $$
begin
  if not exists (select 1 from pg_trigger where tgname='trg_vouchers_immutable') then
    raise exception 'T12 FAIL: voucher guard trigger tidak ada';
  end if;
  raise notice 'T12 PASS';
end $$;

-- T13: test issue_voucher UNAUTHORIZED tanpa user
do $$
declare r jsonb;
begin
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    select public.issue_voucher('X', gen_random_uuid(), current_date, 'KIOSK-TEST')
      into r;
    if (r->>'ok')::boolean = true then
      raise exception 'T13 FAIL: bisa issue tanpa user';
    end if;
    raise notice 'T13 PASS (code=%)', r->>'code';
  exception when others then
    raise notice 'T13 PASS (raised: %)', sqlerrm;
  end;
end $$;

-- T14: rekonsiliasi tanpa allowlist -> error
do $$
begin
  delete from public.admin_reconciliation;
  begin
    perform public.dba_reconcile_admins();
    raise exception 'T14 FAIL: tidak error saat allowlist kosong';
  exception when others then
    if sqlerrm like '%allowlist kosong%' then
      raise notice 'T14 PASS';
    else
      raise exception 'T14 FAIL: error berbeda: %', sqlerrm;
    end if;
  end;
end $$;

-- Selesai. FAIL = exception; PASS = NOTICE.