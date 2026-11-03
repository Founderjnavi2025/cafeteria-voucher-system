# Cafeteria Voucher System (CVS)

Sistem manajemen hak makan karyawan & penerbitan voucher berbasis data kehadiran.

> **Status Proyek:** Fase 0 — Persiapan. Belum ada implementasi migration, backend, atau frontend. Dokumen ini adalah titik awal pembangunan.

---

## Ringkasan

CVS mengelola **hak makan karyawan** berdasarkan data kehadiran, jadwal makan, dan aturan kelayakan yang dapat dikonfigurasi. Sistem menerbitkan **voucher makan** yang dapat dicetak, dengan jaminan:
- Satu karyawan hanya menerima satu voucher per slot makan per tanggal.
- Validasi dilakukan di backend (database), bukan di frontend.
- Semua transaksi tercatat dalam audit log.

**Penerbitan voucher ≠ penukaran makanan.** Keduanya adalah proses terpisah dengan aktor dan otorisasi berbeda.

Dokumen baseline lengkap ada di [`DOCS/BASELINE.md`](DOCS/BASELINE.md) — **wajib dibaca** sebelum berkontribusi.

---

## Ruang Lingkup MVP

| Fitur | Status |
|-------|--------|
| Login administrator | ⏳ Belum |
| Role-based access control | ⏳ Belum |
| Dashboard ringkasan | ⏳ Belum |
| Manajemen karyawan (CRUD) | ⏳ Belum |
| Import CSV karyawan | ⏳ Belum |
| Pencatatan kehadiran (manual + CSV) | ⏳ Belum |
| Konfigurasi slot makan | ⏳ Belum |
| Konfigurasi aturan kelayakan | ⏳ Belum |
| Penerbitan voucher | ⏳ Belum |
| Pencegahan voucher ganda | ⏳ Belum |
| Redeem & cancel voucher | ⏳ Belum |
| Print voucher (thermal-friendly) | ⏳ Belum |
| Halaman scan kiosk | ⏳ Belum |
| Audit log | ⏳ Belum |
| Rekonsiliasi admin (DBA) | ⏳ Belum |

Integrasi hardware (fingerprint, RFID, printer LAN/Bluetooth) **bukan** bagian MVP. Dirancang melalui adapter pattern untuk masa depan.

---

## Stack Teknologi

| Lapisan | Teknologi |
|---------|-----------|
| Frontend | HTML5, CSS3, Vanilla JavaScript |
| Backend & DB | Supabase (PostgreSQL + Auth + RLS + RPC) |
| Hosting | Vercel |
| Source code | GitHub |
| Lingkungan dev awal | Termux Android |

Tanpa framework frontend berat. Tanpa bundler pada MVP (CDN Supabase JS).

---

## Struktur Repo

