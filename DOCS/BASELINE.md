# CAFETERIA VOUCHER SYSTEM (CVS) — BASELINE RESMI PEMBANGUNAN

**Versi Dokumen:** 1.0 (Baseline, Dikonfirmasi)
**Status:** Rancangan Awal — Belum Diimplementasikan, Belum Diuji
**Tanggal Baseline:** 2026-11-03
**Tanggal Konfirmasi:** 2026-11-03
**Dasar:** Seluruh diskusi Tahap 1 + Security Review + Final Review + Koreksi `0006`

> Dokumen ini adalah **pedoman resmi** pembangunan CVS. Tidak ada kode, migration, atau klaim pengujian di dalamnya. Semua keputusan yang tercantum di sini adalah hasil konsolidasi diskusi sebelumnya. Setiap penyimpangan dari dokumen ini harus melalui revisi dokumen baseline.

---

## KONFIRMASI BASELINE

| Item | Keputusan |
|------|-----------|
| **Baseline versi 1.0** | SETUJU — digunakan sebagai acuan resmi pembangunan CVS |
| **Admin sah** | Belum ditentukan. Akan ditetapkan saat persiapan akun Supabase. **Tidak ada email admin yang dibuat/dikarang di dokumen ini.** |
| **Timezone perusahaan** | `Asia/Jakarta` (WIB) untuk sementara. Dapat diubah via `app_settings` saat implementasi. |

---

## 1. IDENTITAS DAN TUJUAN CVS

### 1.1 Identitas
- **Nama Sistem:** Cafeteria Voucher System (CVS)
- **Jenis:** Aplikasi web internal perusahaan
- **Pengguna:** Administrator HR/GA, Operator Kantin, Viewer (audit)
- **Lingkup:** Single-tenant (satu perusahaan), multi-kiosk (banyak titik layanan)

### 1.2 Tujuan
CVS mengelola **hak makan karyawan** berdasarkan:
- Data kehadiran karyawan pada tanggal tertentu.
- Jadwal makan (slot) yang dapat dikonfigurasi.
- Aturan kelayakan yang dapat dikonfigurasi administrator.
- Status kepegawaian karyawan.

CVS menerbitkan **voucher makan** yang dapat dicetak, dengan jaminan:
- Satu karyawan hanya menerima satu voucher per slot makan per tanggal.
- Validasi dilakukan di backend (database), bukan di frontend.
- Semua transaksi tercatat dalam audit log.

### 1.3 Yang CVS BUKAN
- **Bukan** sistem penukaran makanan. Penerbitan voucher ≠ penukaran voucher.
- **Bukan** sistem biometrik. Fingerprint/RFID hanya sebagai adapter identifikasi di masa depan.
- **Bukan** sistem absensi. Data kehadiran **diinput** ke CVS (manual/CSV); integrasi mesin absensi adalah pekerjaan terpisah.
- **Bukan** sistem penggajian atau akuntansi.

---

## 2. HASIL KEPUTUSAN DISKUSI

### 2.1 Keputusan Bisnis
| # | Keputusan | Alasan |
|---|-----------|--------|
| B1 | Penerbitan voucher dan penukaran makanan adalah proses berbeda | Penukaran = event fisik di kantin; sistem MVP hanya menerbitkan |
| B2 | Voucher = 1 per (karyawan × slot makan × tanggal) | Aturan bisnis inti |
| B3 | Duplikat dicegah di level database (unique partial index + RPC atomik) | Frontend tidak boleh dipercaya |
| B4 | Administrator dapat mengonfigurasi slot makan dan aturan kelayakan | Fleksibilitas operasional |
| B5 | Status voucher: `issued`, `redeemed`, `cancelled` | Transisi dibatasi: issued → redeemed/cancelled |
| B6 | Voucher memiliki nomor unik human-readable (`CVS-YYYYMMDD-HHMMSS-RAND`) | Untuk pencetakan dan lookup manual |
| B7 | Device ID hanya identifier, bukan autentikasi perangkat | Sesuai temuan keamanan |
| B8 | Timezone perusahaan dapat dikonfigurasi (default `Asia/Jakarta`) | Fleksibilitas lokasi |
| B9 | Slot makan yang melewati tengah malam secara eksplisit **ditolak** di MVP | Menghindari ambiguitas |

### 2.2 Keputusan Teknologi
| # | Keputusan |
|---|-----------|
| T1 | Frontend: HTML5 + CSS3 + Vanilla JavaScript (tanpa framework berat) |
| T2 | Backend: Supabase (PostgreSQL + Auth + RLS + RPC) |
| T3 | Hosting: Vercel (static hosting + rewrites) |
| T4 | Source code: GitHub |
| T5 | Lingkungan pengembangan awal: Termux Android (dapat dilanjutkan ke mesin lain) |
| T6 | Integrasi hardware: melalui adapter pattern (tidak mengunci ke satu merek) |
| T7 | Tidak menggunakan bundler pada MVP (CDN Supabase JS) |

### 2.3 Keputusan Keamanan
| # | Keputusan | Sumber |
|---|-----------|--------|
| S1 | Role **tidak pernah** diambil dari `raw_user_meta_data` signup; default `operator` | Final Review T-A |
| S2 | Role `admin` hanya dapat ditetapkan via allowlist DBA + prosedur rekonsiliasi | Final Review T-A |
| S3 | Semua `SECURITY DEFINER` memakai `SET search_path = pg_catalog, public` | Final Review T-F |
| S4 | Function dengan ekstensi (mis. `gen_random_bytes`) memakai schema-qualified (`extensions.*`) | Final Review T-F |
| S5 | `issue_voucher` memvalidasi `is_active_operator_or_admin()` sebelum eksekusi | Security Review S3 |
| S6 | `redeem_voucher` & `cancel_voucher` = RPC terpisah; client tidak boleh UPDATE `vouchers` langsung | Final Review T-C |
| S7 | Attendance: INSERT oleh staff; UPDATE/DELETE oleh admin saja | Final Review T-B |
| S8 | Setiap perubahan attendance dicatat di `audit_logs` via trigger | Final Review T-B |
| S9 | Guard privilege columns pada `profiles` via trigger + RLS | Security Review S4/S5 |
| S10 | DBA maintenance path via RPC `dba_reconcile_admins()` (owner-only) — **bukan** GUC sebagai otorisasi | Koreksi C1/C2 |
| S11 | `app_settings` dan `admin_reconciliation` = RLS aktif, tanpa akses client | Koreksi C3 |
| S12 | `device_id` = hint forensik di audit log, bukan bukti | Final Review T-H |
| S13 | Time window issue voucher memakai jam lokal perusahaan; grace period dibatasi agar tidak overflow tengah malam | Koreksi C5 |

### 2.4 Keputusan Data
| # | Keputusan |
|---|-----------|
| D1 | `attendance` menerima input **manual** atau **CSV** pada MVP |
| D2 | Integrasi mesin absensi eksternal = pekerjaan terpisah (butuh migrasi baru, bukan modifikasi skema) |
| D3 | CSV kolom kurang diisi string kosong (didokumentasikan); kolom berlebih = malformed (ditolak) |
| D4 | Header duplikat = malformed |
| D5 | Quote tidak tertutup / karakter setelah closing quote = malformed |
| D6 | Data biometrik mentah **tidak pernah** disimpan di Supabase |

### 2.5 Status Verifikasi (Jujur)
| Item | Status |
|------|--------|
| Desain migration `0001`–`0006` | ✅ Selesai (statis) |
| Eksekusi migration di PostgreSQL | ❌ **Belum dilakukan** |
| Eksekusi test SQL (`0007`) | ❌ **Belum dilakukan** |
| Unit test CSV di browser | ❌ **Belum dilakukan** |
| Manual test M01–M23 | ❌ **Belum dilakukan** |
| Deployment ke Vercel | ❌ **Belum dilakukan** |

Semua item "belum" **wajib** dieksekusi sebelum sistem dinyatakan siap produksi.

---

## 3. ALUR BISNIS SISTEM

### 3.1 Alur Utama (End-to-End)

1] Admin import karyawan (manual / CSV)
│
▼
[2] Data kehadiran diperbarui (input manual / CSV) oleh staff
│
▼
[3] Sistem menentukan kelayakan makan (otomatis saat query / saat issue)
│
▼
[4] Karyawan melakukan identifikasi (input employee_id di kiosk, atau scan)
│
▼
[5] Backend memeriksa hak voucher & duplikasi (RPC issue_voucher)
│
├── NOT eligible / DUPLICATE / UNAUTHORIZED / OUTSIDE_WINDOW → tampilkan pesan
│
▼
[6] Voucher diterbitkan (atomic insert)
│
▼
[7] Voucher dicetak (browser print, thermal-friendly)
│
▼
[8] Aktivitas tercatat di audit_logs
│
▼
[Kemudian, di kantin] Voucher redeemed (RPC redeem_voucher oleh operator kantin)
│
▼
[Optional] Voucher cancelled (RPC cancel_voucher oleh admin, bila salah terbit)


### 3.2 Pemisahan Konsep Kritis

| Konsep | Aktor | Kapan | Efek |
|--------|-------|-------|------|
| **Penerbitan Voucher** | Operator/admin di kiosk | Saat karyawan datang ke kiosk | Insert row `vouchers` status `issued` |
| **Penukaran Voucher** | Operator kantin | Saat makanan diserahkan | Update status `issued` → `redeemed` |
| **Pembatalan Voucher** | Admin | Bila salah terbit / kondisi khusus | Update status `issued` → `cancelled` |

**Penerbitan ≠ Penukaran ≠ Pembatalan.** Ketiganya adalah event terpisah dengan aktor dan otorisasi berbeda.

### 3.3 Eligibility Engine (Ringkas)

Seorang karyawan **eligible** untuk slot makan X pada tanggal T jika dan hanya jika:

1. `employees.employment_status ∈ ('active','contract')`
2. `attendance` ada untuk (employee_id, T)
3. `attendance.attendance_status ∈ required_attendance_statuses` pada rule aktif yang match
4. Rule aktif yang match: `meal_eligibility` dengan `is_active = true`, `meal_schedule_id = X`, dan field `applicable_*` cocok dengan data karyawan
5. Bila multiple rule match → ambil `priority` terkecil

### 3.4 Duplicate Prevention

1. Unique partial index: `(employee_id, meal_schedule_id, voucher_date)` WHERE `status <> 'cancelled'`
2. RPC `issue_voucher` melakukan pre-check + insert dalam transaksi `FOR UPDATE` pada employee row
3. Return `DUPLICATE` + `existing_voucher_no` bila ada

---

## 4. ARSITEKTUR TEKNOLOGI

### 4.1 Diagram Arsitektur
## 4. ARSITEKTUR TEKNOLOGI

### 4.1 Diagram Arsitektur

```

┌─────────────────────────────────────────────────────────────┐
│                       BROWSER (Vercel)                       │
│                                                              │
│  HTML5 + CSS3 + Vanilla JS (multi-page, CDN Supabase JS)    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ pages/       │  │ assets/js/   │  │ assets/css/  │      │
│  │ (views)      │  │ (logic)      │  │ (styles)     │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         │                                                    │
│         │ supabase-js (anon key only, session persisted)    │
└─────────┼───────────────────────────────────────────────────┘
│ HTTPS
▼
┌─────────────────────────────────────────────────────────────┐
│                     SUPABASE (cloud)                         │
│                                                              │
│  ┌────────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │ Auth           │  │ PostgreSQL   │  │ Storage        │  │
│  │ (email + pwd)  │  │ + RLS        │  │ (tidak dipakai │  │
│  │                │  │ + SECURITY   │  │  di MVP)       │  │
│  │                │  │   DEFINER    │  │                │  │
│  │                │  │   RPC        │  │                │  │
│  └────────────────┘  └──────────────┘  └────────────────┘  │
└─────────────────────────────────────────────────────────────┘
▲
│ (Future, di luar MVP)
│
┌─────────┴───────────────────────────────────────────────────┐
│             HARDWARE ADAPTER LAYER (Future)                  │
│  Fingerprint scanner | RFID reader | Thermal printer LAN    │
└─────────────────────────────────────────────────────────────┘

### 4.2 Lapisan Aplikasi

| Lapisan | Tanggung Jawab | Lokasi |
|---------|----------------|--------|
| **Presentation** | Markup, styles, print layout | `pages/`, `assets/css/` |
| **Application Logic** | Auth guard, form handling, CSV parsing, RPC call | `assets/js/` |
| **Security Boundary** | RLS, SECURITY DEFINER RPC, trigger guards | `supabase/migrations/` |
| **Data** | Tables, indexes, constraints | PostgreSQL |
| **Audit** | `audit_logs` via trigger & RPC | PostgreSQL |

### 4.3 Batas Kepercayaan (Trust Boundary)

- **Frontend = tidak dipercaya.** Semua validasi bisnis wajib ada di DB.
- **`anon` key = publik.** Hanya boleh dipakai untuk baca terbatas oleh `authenticated`.
- **`service_role` key = TIDAK BOLEH** ada di frontend.
- **Sesi login = satu-satunya gate.** Device ID bukan autentikasi.

### 4.4 Adapter Pattern untuk Hardware (Future)

Kontrak adapter (rancangan, **bukan implementasi MVP**):
IdentifierAdapter {
identify(): Promise<{ employee_id: string, confidence: number, raw_hash?: string }>
}

```
- Implementasi konkret: `FingerprintAdapter`, `RFIDAdapter`, `ManualInputAdapter`.
- Semua adapter hanya menghasilkan `employee_id`; **tidak** menyimpan biometrik mentah.
- Biometrik mentah tetap di perangkat; server hanya menerima `employee_id`.

---

## 5. STRUKTUR FOLDER

```

cafeteria-voucher-system/
│
├── index.html                          # Entry redirect
├── vercel.json                         # Rewrites & security headers
├── .gitignore
├── README.md
├── DOCS/                               # Dokumen (baseline ini)
│   └── BASELINE.md
│
├── assets/
│   ├── css/
│   │   ├── main.css                    # Tokens, reset, typography
│   │   ├── components.css              # Buttons, cards, tables, forms, badges
│   │   ├── layout.css                  # Sidebar, topbar, responsive
│   │   └── print.css                   # Thermal print (58mm / 80mm)
│   ├── js/
│   │   ├── config.js                   # Konstanta publik (anon key, device id helper)
│   │   ├── supabaseClient.js           # Init client
│   │   ├── auth.js                     # Session, guard, login/logout
│   │   ├── ui.js                       # Toast, loading, escapeHtml
│   │   ├── utils.js                    # CSV parser, date format
│   │   ├── router.js                   # (Future) hash router, tidak wajib MVP
│   │   └── services/                   # (Opsional) kumpulan wrapper RPC
│   │       ├── employees.js
│   │       ├── attendance.js
│   │       ├── eligibility.js
│   │       ├── vouchers.js
│   │       └── dashboard.js
│   └── img/
│       └── logo.svg
│
├── pages/
│   ├── login.html
│   ├── dashboard.html
│   ├── employees.html
│   ├── attendance.html
│   ├── eligibility.html
│   ├── vouchers.html
│   ├── scan.html
│   └── print-voucher.html
│
└── supabase/
└── migrations/
├── 0001_init_schema.sql
├── 0002_rls_policies.sql
├── 0003_seed_admin_helper.sql
├── 0004_security_hardening.sql
├── 0005_final_hardening.sql
├── 0006_fix_0005.sql
└── 0007_security_tests.sql

```

**Catatan:** Folder `services/` bersifat opsional — membantu modularitas tetapi tidak wajib untuk MVP. Boleh dibuat bertahap.

---

## 6. DAFTAR FILE YANG HARUS DIBUAT

Kolom **Status** = apakah dibutuhkan untuk MVP atau nanti.
Kolom **Urut** = urutan pembuatan yang disarankan.

| # | File / Lokasi | Tanggung Jawab | Hubungan | Urut | Status |
|---|---------------|----------------|----------|------|--------|
| 1 | `DOCS/BASELINE.md` | Dokumen ini | Referensi semua file | 0 | MVP |
| 2 | `README.md` | Instruksi setup, deploy, status | Referensi semua | 1 | MVP |
| 3 | `.gitignore` | Hindari commit rahasia | — | 1 | MVP |
| 4 | `supabase/migrations/0001_init_schema.sql` | Skema tabel inti | Dipakai `0002`–`0006` | 2 | MVP |
| 5 | `supabase/migrations/0002_rls_policies.sql` | RLS awal | Bergantung `0001` | 3 | MVP |
| 6 | `supabase/migrations/0003_seed_admin_helper.sql` | Seed meal schedules + rule default | Bergantung `0001` | 3 | MVP |
| 7 | `supabase/migrations/0004_security_hardening.sql` | Perbaikan S2–S5 | Bergantung `0001`–`0003` | 4 | MVP |
| 8 | `supabase/migrations/0005_final_hardening.sql` | Rekonsiliasi admin, timezone, voucher RPC | Bergantung `0004` | 5 | MVP |
| 9 | `supabase/migrations/0006_fix_0005.sql` | Perbaikan DBA path, RLS app_settings, time window | Bergantung `0005` | 6 | MVP |
| 10 | `supabase/migrations/0007_security_tests.sql` | SQL test struktural | Bergantung `0006` | 7 | MVP |
| 11 | `vercel.json` | Rewrites + security headers | — | 8 | MVP |
| 12 | `assets/css/main.css` | Design tokens | Dipakai semua page | 9 | MVP |
| 13 | `assets/css/components.css` | Komponen UI | Dipakai semua page | 9 | MVP |
| 14 | `assets/css/layout.css` | Layout utama | Dipakai page protected | 9 | MVP |
| 15 | `assets/css/print.css` | Print thermal | Dipakai `print-voucher.html` | 9 | MVP |
| 16 | `assets/js/config.js` | Konstanta publik | Dimuat sebelum `supabaseClient.js` | 10 | MVP |
| 17 | `assets/js/supabaseClient.js` | Init `cvsSupabase` | Bergantung `config.js` + CDN | 10 | MVP |
| 18 | `assets/js/auth.js` | Session, guard, login/logout | Bergantung `supabaseClient.js` | 11 | MVP |
| 19 | `assets/js/ui.js` | Toast, loading, escape | Independen | 11 | MVP |
| 20 | `assets/js/utils.js` | CSV parser, date | Independen | 11 | MVP |
| 21 | `assets/js/router.js` | Hash router | Opsional | 12 | Nanti |
| 22 | `assets/js/services/employees.js` | Wrapper RPC/query employee | Bergantung `supabaseClient.js` | 13 | Opsional |
| 23 | `assets/js/services/attendance.js` | Wrapper query attendance | Idem | 13 | Opsional |
| 24 | `assets/js/services/eligibility.js` | Wrapper query eligibility | Idem | 13 | Opsional |
| 25 | `assets/js/services/vouchers.js` | Wrapper `issue_voucher`, `redeem_voucher`, `cancel_voucher` | Idem | 13 | Opsional |
| 26 | `assets/js/services/dashboard.js` | Query agregat dashboard | Idem | 13 | Opsional |
| 27 | `assets/img/logo.svg` | Logo aplikasi | Dipakai `login.html`, sidebar | 9 | MVP |
| 28 | `index.html` | Redirect sesuai sesi | Bergantung `auth.js` | 14 | MVP |
| 29 | `pages/login.html` | Form login | Bergantung `auth.js`, `ui.js` | 14 | MVP |
| 30 | `pages/dashboard.html` | Ringkasan statistik + aktivitas | Bergantung `auth.js`, `ui.js`, RPC/query | 15 | MVP |
| 31 | `pages/employees.html` | CRUD employee + import CSV | Bergantung `auth.js`, `ui.js`, `utils.js` | 15 | MVP |
| 32 | `pages/attendance.html` | Lihat & input attendance + CSV | Idem | 16 | MVP |
| 33 | `pages/eligibility.html` | CRUD meal schedules + rules | Idem | 16 | MVP |
| 34 | `pages/vouchers.html` | Daftar voucher + redeem/cancel | Idem | 17 | MVP |
| 35 | `pages/scan.html` | Kiosk scan/input employee_id | Idem | 17 | MVP |
| 36 | `pages/print-voucher.html` | Print layout voucher | Bergantung `print.css` | 17 | MVP |
| 37 | `DEPLOYMENT.md` | Langkah deploy detail | Opsional | 18 | Nanti |
| 38 | `TESTING.md` | Skenario manual test | Opsional | 18 | Nanti |
| 39 | `adapters/fingerprint.js` (Future) | Adapter fingerprint | Bergantung kontrak adapter | 19 | Nanti |
| 40 | `adapters/rfid.js` (Future) | Adapter RFID | Idem | 19 | Nanti |
| 41 | `adapters/printer.js` (Future) | Adapter printer thermal | Idem | 19 | Nanti |

**Catatan:** File `services/*` opsional. Bila dibuat, memudahkan pengujian unit & maintainability. Bila tidak, logic RPC langsung di page.

---

## 7. RANCANGAN DATABASE

> **Status:** Rancangan. Belum dieksekusi. Migration lengkap sudah dirancang di `0001`–`0006` (bahan diskusi). Dokumen ini hanya menetapkan **kontrak**, bukan SQL.

### 7.1 Tabel

#### `profiles`
- **PK:** `id` (uuid, FK → `auth.users.id`)
- **Kolom:** `email` (unique), `full_name`, `role` (`admin`/`operator`/`viewer`), `is_active`, `created_at`, `updated_at`
- **Relasi:** 1:1 dengan `auth.users`
- **Guard:** trigger `guard_profile_privilege_columns` menolak perubahan `role`/`is_active`/`email` oleh non-admin (kecuali jalur maintenance DBA)

#### `employees`
- **PK:** `id` (uuid)
- **Unique:** `employee_id` (text)
- **Kolom:** `full_name`, `department`, `position`, `shift`, `employment_status`, timestamps
- **Enum check:** `shift ∈ (day, night, morning, evening, off)`, `employment_status ∈ (active, inactive, contract, resigned)`
- **Relasi:** dirujuk oleh `attendance`, `vouchers`

#### `meal_schedules`
- **PK:** `id` (uuid)
- **Unique:** `code` (breakfast/lunch/dinner/custom)
- **Kolom:** `name`, `start_time` (time), `end_time` (time), `is_active`, timestamps
- **Aturan:** `start_time < end_time` wajib (slot lintas tengah malam ditolak)

#### `attendance`
- **PK:** `id` (uuid)
- **Unique:** `(employee_id, attendance_date)`
- **Kolom:** `check_in`, `check_out`, `attendance_status` (present/late/absent/leave/sick/holiday), `shift`, `notes`, timestamps
- **Relasi:** FK `employee_id` → `employees.employee_id`
- **Audit:** trigger `trg_attendance_audit` mencatat semua perubahan
- **Sumber data MVP:** manual + CSV. Integrasi mesin absensi = pekerjaan terpisah

#### `meal_eligibility`
- **PK:** `id` (uuid)
- **Kolom:** `name`, `meal_schedule_id` (FK), `applicable_department`, `applicable_shift`, `applicable_status`, `required_attendance_statuses` (text[]), `is_active`, `priority`, timestamps
- **Perilaku:** NULL = berlaku untuk semua. Multiple match → ambil `priority` terkecil.
- **Audit:** trigger `trg_eligibility_audit`

#### `vouchers`
- **PK:** `id` (uuid)
- **Unique:** `voucher_no` (text)
- **Unique partial index:** `(employee_id, meal_schedule_id, voucher_date)` WHERE `status <> 'cancelled'` — **anti-duplikat**
- **Kolom:** `employee_id` (FK), `meal_schedule_id` (FK), `voucher_date`, `status` (issued/redeemed/cancelled), `issued_at`, `issued_by` (FK profiles), `device_id`, `redeemed_at`, `cancelled_at`, `cancel_reason`
- **Immutable via trigger:** `id`, `voucher_no`, `employee_id`, `meal_schedule_id`, `voucher_date`, `issued_at`, `issued_by`, `device_id`
- **Transisi status:** hanya `issued → redeemed` atau `issued → cancelled`
- **Akses:** client tidak punya INSERT/UPDATE policy → semua lewat RPC

#### `audit_logs`
- **PK:** `id` (uuid)
- **Kolom:** `actor_id` (FK profiles, nullable), `action` (text), `entity_type`, `entity_id`, `metadata` (jsonb), `ip_address`, `user_agent`, `created_at`
- **Akses:** client tidak bisa INSERT; hanya SECURITY DEFINER RPC/trigger

#### `app_settings`
- **PK:** `key` (text)
- **Kolom:** `value`, `updated_at`
- **Seed:** `meal_timezone = 'Asia/Jakarta'`
- **Akses:** RLS aktif, tidak ada policy untuk client. Baca via `app_timezone()`.

#### `admin_reconciliation`
- **PK:** `email` (text)
- **Kolom:** `note`, `created_at`
- **Peran:** allowlist admin sah untuk prosedur rekonsiliasi
- **Akses:** RLS aktif, tidak ada policy untuk client. Hanya DBA via SQL Editor.

### 7.2 Fungsi Database (RPC)

| Fungsi | Otorisasi | Tujuan |
|--------|-----------|--------|
| `is_admin()` | authenticated | Cek role admin aktif |
| `is_staff()` | authenticated | Cek role admin/operator aktif |
| `is_active_operator_or_admin()` | authenticated | Cek operator/admin aktif |
| `app_timezone()` | authenticated | Baca timezone dari `app_settings` |
| `issue_voucher(employee_id, meal_schedule_id, voucher_date, device_id)` | operator/admin aktif | Terbitkan voucher atomik |
| `redeem_voucher(voucher_id)` | operator/admin aktif | Tandai redeemed |
| `cancel_voucher(voucher_id, reason)` | operator/admin aktif | Tandai cancelled |
| `dba_reconcile_admins()` | owner (postgres/supabase_admin) | Rekonsiliasi admin |

### 7.3 Aturan Validasi Backend (Wajib)

`issue_voucher` **HARUS** memeriksa (dalam urutan):
1. Pemanggil = operator/admin aktif
2. Schedule aktif & ditemukan
3. `start_time < end_time` (tolak slot malam)
4. `voucher_date = today` (timezone perusahaan)
5. Waktu sekarang dalam `[start_time, min(end_time + 60m, 23:59:59)]`
6. Employee ada & status aktif
7. Attendance ada & status sesuai rule
8. Rule eligibility match
9. Tidak ada voucher duplikat (pre-check)
10. Insert atomik (unique index sebagai jaring terakhir)

Semua kondisi **gagal** = return JSON `{ok:false, code:..., message:...}`. Tidak ada silent failure.

### 7.4 Index Wajib

| Tabel | Index | Alasan |
|-------|-------|--------|
| `employees` | `employee_id` | Lookup |
| `employees` | `employment_status`, `department` | Filter |
| `attendance` | `attendance_date` | Query harian |
| `attendance` | `employee_id` | FK |
| `vouchers` | unique partial (anti-dup) | Bisnis inti |
| `vouchers` | `voucher_date`, `status`, `employee_id` | Query |
| `audit_logs` | `created_at` desc, `action` | Riwayat |

---

## 8. RANCANGAN KEAMANAN

### 8.1 Matriks Akses (Role × Operasi)

| Operasi | anon | viewer | operator | admin | owner (DBA) |
|---------|------|--------|----------|-------|-------------|
| Login | ✅ (auth) | ✅ | ✅ | ✅ | — |
| Baca `profiles` (self) | ❌ | ✅ | ✅ | ✅ | ✅ |
| Baca `profiles` (all) | ❌ | ❌ | ❌ | ✅ | ✅ |
| Update `profiles` (self, non-sensitif) | ❌ | ❌ | ✅ | ✅ | ✅ |
| Update `profiles.role/is_active` | ❌ | ❌ | ❌ | ✅ | ✅ (via jalur maintenance) |
| Baca `employees` | ❌ | ✅ | ✅ | ✅ | ✅ |
| CRUD `employees` | ❌ | ❌ | ❌ | ✅ | ✅ |
| Insert `attendance` | ❌ | ❌ | ✅ | ✅ | ✅ |
| Update/Delete `attendance` | ❌ | ❌ | ❌ | ✅ | ✅ |
| CRUD `meal_schedules` | ❌ | ❌ | ❌ | ✅ | ✅ |
| CRUD `meal_eligibility` | ❌ | ❌ | ❌ | ✅ | ✅ |
| Baca `vouchers` | ❌ | ✅ | ✅ | ✅ | ✅ |
| INSERT/UPDATE `vouchers` langsung | ❌ | ❌ | ❌ | ❌ | ❌ |
| RPC `issue_voucher` | ❌ | ❌ | ✅ | ✅ | ✅ |
| RPC `redeem_voucher` | ❌ | ❌ | ✅ | ✅ | ✅ |
| RPC `cancel_voucher` | ❌ | ❌ | ✅ | ✅ | ✅ |
| Baca `audit_logs` | ❌ | ❌ | ❌ | ✅ | ✅ |
| INSERT `audit_logs` | ❌ | ❌ | ❌ | ❌ | ✅ (via definer) |
| Baca/Update `app_settings` | ❌ | ❌ | ❌ | ❌ | ✅ (SQL Editor) |
| Baca/Update `admin_reconciliation` | ❌ | ❌ | ❌ | ❌ | ✅ (SQL Editor) |
| RPC `dba_reconcile_admins` | ❌ | ❌ | ❌ | ❌ | ✅ |

### 8.2 Prinsip Wajib

1. **Zero Trust Frontend.** Semua gate ada di DB.
2. **Least Privilege.** Setiap function hanya di-`EXECUTE` ke role yang perlu.
3. **Search Path Aman.** `SET search_path = pg_catalog, public` untuk semua `SECURITY DEFINER`.
4. **No `service_role` di Frontend.** Hanya `anon` key.
5. **No Raw Biometrics.** Data biometrik tidak pernah tersimpan.
6. **Audit Trail Immutable.** Client tidak bisa INSERT `audit_logs`.
7. **Defense in Depth.** Trigger + RLS + RPC + constraint, bukan satu lapis.
8. **Jalur DBA Terpisah.** Rekonsiliasi admin & ubah settings hanya via SQL Editor (owner role), bukan RPC client.

### 8.3 Rekonsiliasi Admin (Kebijakan Resmi)

1. Admin sah **wajib** di-allowlist di `admin_reconciliation` oleh DBA.
2. Prosedur:
   - Backup DB.
   - Isi `admin_reconciliation` dengan email admin yang **diverifikasi**.
   - Panggil `select public.dba_reconcile_admins();` via SQL Editor sebagai postgres/supabase_admin.
   - Semua `admin` yang tidak ada di allowlist → turun ke `operator`.
   - Semua penurunan tercatat di `audit_logs`.
3. **Admin tidak dipertahankan otomatis.** "Tidak ada di allowlist" = diturunkan.
4. Bila allowlist kosong → prosedur **gagal** (tidak menurunkan siapa pun) dengan pesan eksplisit.
5. **Status saat ini:** allowlist belum diisi. Akan diisi saat persiapan akun Supabase.

### 8.4 Batas Keamanan yang Diakui

- **Device ID** bukan autentikasi. Dapat dipalsukan.
- **CSV import** dapat berisi data palsu (operator bisa memasukkan attendance palsu). Kontrol: audit log mencatat operator.
- **Attendance UPDATE** dibatasi ke admin untuk mencegah operator memanipulasi eligibility.
- **Mesin absensi eksternal** belum terintegrasi; memerlukan jalur service-account khusus (bukan MVP).

### 8.5 Testing Keamanan (Wajib Sebelum Production)

- `0007_security_tests.sql` dijalankan di staging → semua `NOTICE ... PASS`.
- Manual test M01–M23 di browser/REST.
- CSV unit test di browser console → 12/12 `ok: true`.
- Uji migrasi `0006` di staging dengan data dummy admin (T14 di `0007`).

---

## 9. FITUR MVP

### 9.1 Dalam Lingkup MVP

| # | Fitur | Prioritas | Catatan |
|---|-------|-----------|---------|
| F1 | Login administrator | P0 | Supabase Auth |
| F2 | Role-based access control | P0 | admin / operator / viewer |
| F3 | Dashboard ringkasan | P0 | Statistik + aktivitas |
| F4 | Manajemen karyawan (CRUD) | P0 | + pencarian |
| F5 | Import CSV karyawan | P0 | Validasi duplikat `employee_id` |
| F6 | Pencatatan kehadiran | P0 | Manual + CSV |
| F7 | Konfigurasi slot makan | P0 | Meal schedules |
| F8 | Konfigurasi aturan kelayakan | P0 | Meal eligibility |
| F9 | Penerbitan voucher | P0 | RPC atomik |
| F10 | Pencegahan voucher ganda | P0 | Unique partial index + RPC |
| F11 | Redeem voucher | P0 | RPC terpisah |
| F12 | Cancel voucher | P0 | RPC terpisah + reason |
| F13 | Print voucher (thermal-friendly) | P0 | Browser print |
| F14 | Halaman scan kiosk | P0 | Input employee_id manual |
| F15 | Audit log | P0 | Trigger otomatis |
| F16 | Rekonsiliasi admin (DBA) | P0 | Prosedur SQL Editor |

### 9.2 Di Luar Lingkup MVP (Future)

- ❌ Integrasi mesin absensi eksternal (hardware fingerprint/RFID)
- ❌ Adapter printer thermal LAN/Bluetooth (cetak pakai browser print)
- ❌ Aplikasi Android native
- ❌ Offline mode / PWA
- ❌ Multi-tenant
- ❌ Notifikasi email/WA
- ❌ Laporan analitik lanjutan
- ❌ Import CSV dengan digital signature
- ❌ Hardware attestation untuk device

---

## 10. DAFTAR PR (PRODUCT BACKLOG)

### 10.1 MVP — Wajib Selesai Sebelum Production

| ID | Judul | Kategori | Dependensi |
|----|-------|----------|-----------|
| PR-01 | Setup repo GitHub + `.gitignore` + README | Infra | — |
| PR-02 | Tulis migration `0001` di repo | DB | PR-01 |
| PR-03 | Tulis migration `0002` RLS | DB | PR-02 |
| PR-04 | Tulis migration `0003` seed | DB | PR-02 |
| PR-05 | Tulis migration `0004` security hardening | DB/Sec | PR-03, PR-04 |
| PR-06 | Tulis migration `0005` final hardening | DB/Sec | PR-05 |
| PR-07 | Tulis migration `0006` fix | DB/Sec | PR-06 |
| PR-08 | Tulis `0007` security test SQL | Testing | PR-07 |
| PR-09 | Setup Supabase project + jalankan `0001`–`0007` di staging | Infra | PR-02..PR-08 |
| PR-10 | Buat admin pertama + seed allowlist + rekonsiliasi | Ops | PR-09 |
| PR-11 | Buat `vercel.json` + connect repo ke Vercel | Infra | PR-01 |
| PR-12 | Buat CSS: `main`, `components`, `layout`, `print` | Frontend | PR-01 |
| PR-13 | Buat `config.js`, `supabaseClient.js` | Frontend | PR-11 |
| PR-14 | Buat `auth.js`, `ui.js`, `utils.js` | Frontend | PR-13 |
| PR-15 | Buat `index.html` + `pages/login.html` | Frontend | PR-14 |
| PR-16 | Buat layout aplikasi (sidebar, topbar) reusable | Frontend | PR-12, PR-15 |
| PR-17 | Buat `pages/dashboard.html` + query agregat | Frontend | PR-16 |
| PR-18 | Buat `pages/employees.html` + CRUD + CSV import | Frontend | PR-16, PR-03 |
| PR-19 | Buat `pages/attendance.html` + manual + CSV | Frontend | PR-16, PR-03 |
| PR-20 | Buat `pages/eligibility.html` (schedules + rules) | Frontend | PR-16, PR-03 |
| PR-21 | Buat `pages/scan.html` + panggilan `issue_voucher` | Frontend | PR-16, PR-07 |
| PR-22 | Buat `pages/print-voucher.html` | Frontend | PR-12 |
| PR-23 | Buat `pages/vouchers.html` + `redeem_voucher` + `cancel_voucher` | Frontend | PR-16, PR-07 |
| PR-24 | Jalankan `0007` security test di staging | Testing | PR-09 |
| PR-25 | Jalankan manual test M01–M23 | Testing | PR-24 |
| PR-26 | Jalankan CSV unit test (browser console) | Testing | PR-14 |
| PR-27 | Uji end-to-end issue voucher + duplicate prevention | Testing | PR-21 |
| PR-28 | Uji print voucher pada thermal 58mm/80mm | Testing | PR-22 |
| PR-29 | Uji responsif tablet (min 768px) | Testing | PR-16..PR-23 |
| PR-30 | Deploy production + smoke test | Infra | semua MVP |

### 10.2 Lanjutan — Setelah MVP Stabil

| ID | Judul | Kategori |
|----|-------|----------|
| PR-31 | Integrasi mesin absensi eksternal (service account khusus) | Integrasi |
| PR-32 | Adapter fingerprint | Hardware |
| PR-33 | Adapter RFID | Hardware |
| PR-34 | Adapter thermal printer LAN/Bluetooth | Hardware |
| PR-35 | Aplikasi kiosk Android (WebView / native wrapper) | Hardware |
| PR-36 | Laporan analitik lanjutan (voucher/day, per dept) | Fitur |
| PR-37 | Notifikasi operator saat voucher gagal | Fitur |
| PR-38 | Bulk operations (redeem massal) | Fitur |
| PR-39 | Backup otomatis + retensi audit log | Ops |
| PR-40 | Dokumentasi pengguna (manual kiosk) | Dokumentasi |

---

## 11. URUTAN PEMBANGUNAN DARI NOL

Berikut urutan **eksekusi** yang harus dilakukan (bukan urutan teoretis). Setiap langkah harus selesai sebelum lanjut.

### Fase 0 — Persiapan (Hari 1)
1. Buat repo GitHub `cafeteria-voucher-system`.
2. Buat file `.gitignore`, `README.md`, `DOCS/BASELINE.md` (dokumen ini).
3. Commit awal.

### Fase 1 — Fondasi DB (Hari 1–3)
4. Tulis migration `0001` di repo.
5. Buat project Supabase staging.
6. Jalankan `0001` di staging via SQL Editor.
7. **Verifikasi tabel + relasi + index** (query manual).
8. Tulis & jalankan `0002` (RLS).
9. Tulis & jalankan `0003` (seed).
10. Tulis & jalankan `0004` (hardening).
11. Tulis & jalankan `0005` (final hardening) — **baca §8.3 dulu**.
12. Tulis & jalankan `0006` (fix).
13. Tulis & jalankan `0007` (security test) → semua PASS.
14. Isi `admin_reconciliation`, jalankan `dba_reconcile_admins()`.
15. Buat 3 akun uji: admin, operator, viewer.

### Fase 2 — Fondasi Frontend (Hari 3–5)
16. Tulis `vercel.json`.
17. Tulis CSS: `main`, `components`, `layout`, `print`.
18. Tulis `config.js`, `supabaseClient.js`.
19. Tulis `auth.js`, `ui.js`, `utils.js`.
20. Tulis `index.html`, `pages/login.html`.
21. Deploy preview ke Vercel → uji login sukses/gagal.

### Fase 3 — Modul Inti (Hari 5–10)
22. Tulis layout aplikasi reusable (dipakai semua page protected).
23. Tulis `pages/dashboard.html`.
24. Tulis `pages/employees.html` + CSV import.
25. Tulis `pages/attendance.html` + CSV import.
26. Tulis `pages/eligibility.html`.

### Fase 4 — Voucher Flow (Hari 10–13)
27. Tulis `pages/scan.html` (panggil `issue_voucher`).
28. Tulis `pages/print-voucher.html`.
29. Tulis `pages/vouchers.html` (redeem/cancel via RPC).
30. Uji end-to-end: import karyawan → attendance → issue → redeem.
31. Uji duplicate prevention (sequential + concurrent).

### Fase 5 — Testing & Deployment (Hari 13–15)
32. Jalankan `0007` di staging (final).
33. Jalankan manual test M01–M23.
34. Jalankan CSV unit test.
35. Uji print thermal.
36. Uji responsif tablet (Chrome DevTools → tablet preset).
37. Deploy production.
38. Smoke test production dengan akun uji.
39. **Serahkan ke pengguna** dengan dokumentasi.

### Fase 6 — Post-MVP (setelah rilis stabil)
40. PR-31 s.d. PR-40 sesuai prioritas bisnis.

---

## 12. LANGKAH PERTAMA YANG HARUS DIKERJAKAN

**Status:** Langkah 1 (konfirmasi baseline) selesai. Langkah 2 (tiga file awal) sedang/sudah dieksekusi.

### Langkah yang sudah selesai
- [x] Konfirmasi baseline v1.0 sebagai rujukan resmi.
- [x] Timezone perusahaan: `Asia/Jakarta` (sementara).
- [x] Admin sah: **belum ditentukan** (akan diisi saat persiapan Supabase).
- [x] Buat `DOCS/BASELINE.md`.
- [x] Buat `.gitignore`.
- [x] Buat `README.md`.

### Langkah berikutnya (belum dieksekusi)
- [ ] Fase 1 — mulai dengan membuat migration `0001` di repo dan project Supabase staging.

---

## PERNYATAAN STATUS

- Dokumen ini **tidak mengklaim** implementasi atau pengujian telah dilakukan.
- Dokumen ini **tidak menambahkan** fitur di luar yang telah didiskusikan.
- Dokumen ini **tidak mengulang** perdebatan SQL `0001`–`0007`; rincian SQL tetap di file migration masing-masing.
- Semua temuan keamanan dari diskusi **dipertahankan** di §2.3 dan §8.
- Setiap penyimpangan dari dokumen ini **wajib** melalui revisi baseline (versi 1.1, 1.2, dst.).

---

**BASELINE v1.0 — DIKONFIRMASI SEBAGAI FONDASI RESMI PEMBANGUNAN CVS.**
```
