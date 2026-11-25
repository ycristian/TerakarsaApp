# Prompt 94 — CCTV: Lihat Rekaman dari Transaksi

Lanjutan Prompt 93. Mockup: `claude prompt/cctv/mockup/Transaksi.dc.html` (tabel di
mockup hanya contoh halaman; yang dibuat adalah tombol + panel di sebelah kanan).

## 0. Inspeksi dulu

- Halaman Laporan Bundle (`/report-bundle`), tab **Riwayat**: komponen timeline, dan
  data yang tersedia per baris (waktu selesai `CreatedAt`, resource pelaksana, divisi).
  Pastikan id resource dan id divisi ikut dikembalikan SP timeline; kalau hanya nama,
  catat SP mana yang perlu ditambah kolom **di akhir** SELECT.
- Cara Client mengecek user punya module tertentu (untuk menyembunyikan tombol).

## 1. SQL

`cctv.SIS_Camera_ForEvent` (`@ResourceId` INT = NULL, `@DivisionId` INT = NULL):
- Kamera hidup yang tertaut ke `@ResourceId`; kalau tidak ada, yang tertaut ke
  `@DivisionId`. Urut `sort_order`.
- Result set kedua: kamera lain di **area** yang sama dengan kamera pertama (untuk
  dropdown "Kamera lain di area ini").

## 2. API

`GET api/cctv/cameras/for-event?resourceId=&divisionId=` (`[RequireModule("CCTV")]`)
→ `{ cameras: [...], others: [...] }`.

Kalau timeline bundle belum membawa id resource/divisi: tambahkan kolomnya di akhir
SELECT SP timeline itu (satu-satunya perubahan yang diizinkan pada SP lama; tidak ada
perubahan logika).

## 3. Client

Komponen bersama `Pages/Cctv/Shared/CctvEventButton.razor`:
- Parameter: `EventTime` (DateTime), `ResourceId` (int?), `DivisionId` (int?),
  `Title` (teks ringkas transaksi untuk judul panel).
- Tidak dirender sama sekali kalau user tidak punya module `CCTV`.
- Tombol kecil **Lihat** (ikon kamera). Diklik → panel samping (offcanvas; di HP layar
  penuh) "CCTV saat kejadian":
  - Subjudul = `Title` + waktu kejadian.
  - Tidak ada kamera tertaut → teks "Belum ada kamera untuk station ini" + tautan ke
    `/cctv/kamera`.
  - Ada → putar rekaman kamera pertama dari **30 detik sebelum** sampai **60 detik
    sesudah** `EventTime` (satu permintaan playback 90 detik, memakai rute Prompt 93).
  - Bar kecil dengan penanda oranye di posisi waktu scan, label jam awal · "scan
    HH:mm:ss" · jam akhir.
  - Dropdown **Kamera lain di area ini** → ganti kamera, rentang waktu sama.
  - **Buka di Playback** → `/cctv/playback?cameraId=&at=` (30 detik sebelum kejadian),
    **Unduh klip** (90 detik itu).
  - Kejadian < 15 detik yang lalu (rekaman belum tertulis) → pesan "Rekaman belum
    tersedia, coba beberapa saat lagi".
- Pasang di tab Riwayat Laporan Bundle: satu tombol per baris timeline, memakai waktu
  selesai step, resource pelaksana, dan divisi step.

## 4. Verifikasi

1. Build sukses.
2. Baris dengan resource tertaut → panel memutar rekaman; penanda waktu scan benar.
3. Baris tanpa tautan resource tapi divisinya tertaut → memakai kamera divisi.
4. Baris tanpa tautan sama sekali → pesan "Belum ada kamera…".
5. User tanpa module `CCTV` → tombol tidak muncul, tampilan Riwayat sama seperti
   sebelumnya (regresi).

## Yang TIDAK boleh dilakukan

- Jangan memasang tombol di halaman lain (station, absensi, benang, TNI) — menyusul.
- Jangan mengubah logika SP timeline/scan; hanya boleh menambah kolom di akhir SELECT.
- Jangan menyimpan klip ke server.

Isi bagian "Prompt 94" dan seluruh bagian penutup laporan, lalu commit (termasuk file
laporan).
