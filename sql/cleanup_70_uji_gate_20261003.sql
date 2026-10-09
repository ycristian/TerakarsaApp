-- Prompt 70 -- Bersihkan data UJI COBA gate tanggal 2026-10-03 pagi (05:40 - 06:19).
-- SEKALI JALAN, bukan bagian skema. Dicek 2026-10-03 sebelum script ini dibuat:
--   * gate_taps           : 44 baris, semuanya 2026-10-03 05:40:53 .. 06:19:52 (uji coba)
--   * attendance_sessions : 13 baris (id 7-19), semuanya dibuat 05:43 .. 06:19 (uji coba),
--                           termasuk sesi ANOMALI hasil tap masuk ganda sebelum aturan
--                           "masuk setelah masuk" diperbaiki
--   * employee_cards      : 9 dari 12 baris adalah UID terpotong akibat bug input reader
--                           GateApp (digit hilang lalu ditambal nol) atau duplikat NONAKTIF.
--                           DISISAKAN 3 kartu asli yang terbaca utuh 10 digit:
--                             id 3  2005381655  EM0001 Yosef Ivander
--                             id 9  1650450826  EM0002 Bundle Emp Test
--                             id 14 2005963559  EM0004 ARIFIN
-- Hapus fisik (bukan soft delete) karena seluruhnya data uji, bukan riwayat sungguhan.
-- Batas waktu < 06:20 (tap uji terakhir 06:19:52) menjaga supaya tap/sesi sungguhan setelah
-- uji coba tidak ikut terhapus -- check in sungguhan pertama tercatat 06:49, jadi batas 07:00
-- yang dulu dipakai di sini akan ikut menghapusnya kalau script dijalankan ulang.

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;   -- WAJIB di sqlcmd: keempat tabel absensi punya filtered index
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

-- gate_taps dulu (FK_gt_sessions -> attendance_sessions)
DELETE FROM gate_taps
WHERE tapped_at >= '2026-10-03 05:00' AND tapped_at < '2026-10-03 06:20';
PRINT CONCAT('gate_taps dihapus: ', @@ROWCOUNT);

DELETE FROM attendance_sessions
WHERE created_at >= '2026-10-03 05:00' AND created_at < '2026-10-03 06:20';
PRINT CONCAT('attendance_sessions dihapus: ', @@ROWCOUNT);

DELETE FROM employee_cards
WHERE employee_card_id IN (4, 5, 6, 7, 8, 10, 11, 12, 13)
  AND created_at >= '2026-10-03 05:00' AND created_at < '2026-10-03 06:20';
PRINT CONCAT('employee_cards dihapus: ', @@ROWCOUNT);

COMMIT TRANSACTION;

-- Hasil yang diharapkan: 3 kartu AKTIF (id 3, 9, 14).
SELECT c.employee_card_id, c.card_uid, c.card_status, e.employee_code, e.employee_name
FROM employee_cards c
INNER JOIN employees e ON e.employee_id = c.employee_id
ORDER BY c.employee_card_id;
