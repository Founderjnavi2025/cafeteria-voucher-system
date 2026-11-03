# TESTING — Cafeteria Voucher System

Panduan pengujian MVP. **Belum dijalankan** — hasil aktual diisi setelah pengujian.

---

## Prasyarat

- Migration `0001`–`0005` sudah dijalankan.
- `0005_security_tests.sql` lulus (semua `NOTICE ... PASS`).
- Akun uji: `admin@…`, `operator@…`, `viewer@…`.
- Data minimal: ≥ 3 karyawan, 1 attendance hari ini, 3 meal_schedules, 1 rule eligibility.

---

## A. Database & Security (SQL)

Jalankan `supabase/migrations/0005_security_tests.sql` di SQL Editor **staging**.

| Test | Langkah | Ekspektasi |
|------|---------|-----------|
| T01 | Jalankan file | RLS aktif di semua tabel |
| T02 | Idem | Semua SECURITY DEFINER punya `search_path=pg_catalog, public` |
| T03 | Idem | anon tidak punya EXECUTE RPC apapun |
| T04 | Idem | authenticated tidak punya EXECUTE `dba_reconcile_admins` |
| T05 | Idem | Tidak ada policy write di `vouchers` |
| T06 | Idem | Unique partial index ada |
| T07 | Idem | authenticated tidak bisa SELECT `app_settings` |
| T08 | Idem | Trigger guard profile ada |
| T09 | Idem | Seed schedules & eligibility ada |
| T10 | Idem | `meal_timezone` seed ada |
| T11 | Idem | Trigger attendance audit ada |
| T12 | Idem | Trigger voucher guard ada |
| T13 | Idem | `issue_voucher` tanpa user → gagal |
| T14 | Idem | `dba_reconcile_admins` tanpa allowlist → error |

---

## B. Authentication

| # | Langkah | Ekspektasi |
|---|---------|-----------|
| B01 | Buka `/login`, isi email+password salah | Toast error, tetap di login |
| B02 | Isi benar (admin) | Redirect ke `/dashboard` |
| B03 | Akses `/dashboard` tanpa login | Redirect ke `/login` |
| B04 | Login sebagai `viewer`, akses `/scan` | Redirect ke `/dashboard` |
| B05 | Klik Logout | Redirect ke `/login`, session dihapus |
| B06 | Refresh `/dashboard` setelah login | Tetap di dashboard (session persist) |
| B07 | Cek Application → Local Storage | Hanya `cvs-auth` (Supabase) dan `cvs_device_id` |

---

## C. Karyawan (CRUD + CSV)

| # | Langkah | Ekspektasi |
|---|---------|-----------|
| C01 | Login admin, buka `/employees`, klik Tambah | Modal terbuka |
| C02 | Isi employee_id `EMP999`, nama, submit | Toast success, muncul di tabel |
| C03 | Coba tambah `EMP999` lagi | Error duplicate key (constraint) |
| C04 | Edit karyawan | Nilai berubah |
| C05 | Klik Nonaktifkan | Status jadi `resigned` |
| C06 | Login `operator`, buka `/employees` | Tidak ada tombol Tambah/Edit/Nonaktifkan/Import |
| C07 | Search "EMP999" | Hanya baris EMP999 |
| C08 | Import CSV valid (5 baris baru) | Toast success, 5 baris muncul |
| C09 | Import CSV dengan duplikat di file | Error "Duplikat ID di CSV" |
| C10 | Import CSV dengan ID yang sudah ada di DB | Toast "Baru: X, dilewati: Y" |
| C11 | Import CSV dengan header kurang | Error "Kolom wajib tidak ada: …" |
| C12 | Import CSV malformed (`"abc` tanpa tutup) | Error "quote tidak ditutup" |

CSV contoh valid:
```csv
employee_id,full_name,department,position,shift,employment_status
EMP100,Andi Wijaya,Produksi,Operator,day,active
EMP101,Siti Rahayu,HR,Staff,day,active
EMP102,Budi Santoso,Produksi,Supervisor,day,contract
