-- Ubah format period_code payroll_periods: '2026-P01' -> '26-w01'.
--   YY = 2 digit terakhir period_year, 'w' kecil, NN = period_no 2 digit.
-- Nomor periode (period_year/period_no) dan rentang tanggal TIDAK berubah -- hanya labelnya.
--
-- Idempotent: hanya baris yang kodenya belum sesuai format baru yang di-UPDATE, jadi
-- aman dijalankan berulang. Tidak ada tabel/kolom yang di-drop (varchar(10) masih muat).
--
-- Jalankan SETELAH sql/alter_55_workflow_lock.sql, dan barengan dengan versi baru
-- sql/sp_PayrollPeriod_Manage.sql (GENERATE_YEAR sudah memakai format yang sama).

SET NOCOUNT ON;
GO

-- 1. Pastikan tidak ada bentrok unique index sebelum menulis (format lama & baru tidak
--    pernah bertabrakan, tapi cek ini menjaga kalau ada kode manual yang sudah diubah).
IF EXISTS (
    SELECT 1
    FROM payroll_periods pp
    WHERE pp.deleted_at IS NULL
    GROUP BY RIGHT(CAST(pp.period_year AS VARCHAR(4)), 2) + '-w' + RIGHT('00' + CAST(pp.period_no AS VARCHAR(2)), 2)
    HAVING COUNT(*) > 1
)
BEGIN
    RAISERROR('Ada period_year/period_no kembar -- format baru akan bentrok. Perbaiki data dulu.', 16, 1);
    RETURN;
END
GO

-- 2. Ganti label. Dihitung dari period_year/period_no, bukan parsing kode lama,
--    supaya tidak bergantung pada format sebelumnya.
UPDATE pp
SET pp.period_code = RIGHT(CAST(pp.period_year AS VARCHAR(4)), 2) + '-w' + RIGHT('00' + CAST(pp.period_no AS VARCHAR(2)), 2)
FROM payroll_periods pp
WHERE pp.period_code <> RIGHT(CAST(pp.period_year AS VARCHAR(4)), 2) + '-w' + RIGHT('00' + CAST(pp.period_no AS VARCHAR(2)), 2);

SELECT @@ROWCOUNT AS BarisDiubah;
GO

-- 3. Verifikasi: semua kode sudah berformat baru (tidak ada baris keluar = beres).
SELECT payroll_period_id, period_year, period_no, period_code
FROM payroll_periods
WHERE period_code <> RIGHT(CAST(period_year AS VARCHAR(4)), 2) + '-w' + RIGHT('00' + CAST(period_no AS VARCHAR(2)), 2);
GO

SELECT TOP 10 period_code, period_start, period_end
FROM payroll_periods
WHERE deleted_at IS NULL
ORDER BY period_start ASC;
GO
