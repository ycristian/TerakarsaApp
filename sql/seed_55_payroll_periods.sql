-- Prompt 55: seed periode gajian 2026 & 2027 lewat SIS_PayrollPeriod_Manage GENERATE_YEAR.
-- Idempotent -- GENERATE_YEAR hanya menambah nomor periode yang belum ada, jadi script ini
-- aman dijalankan berulang (mis. setelah tahun berikutnya perlu ditambah).
-- Jalankan SETELAH sql/alter_55_workflow_lock.sql dan sql/sp_PayrollPeriod_Manage.sql.

SET NOCOUNT ON;

DECLARE @AdminUserId INT = (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id);

IF @AdminUserId IS NULL
BEGIN
    RAISERROR('User Admin tidak ditemukan -- tidak bisa mengisi created_by periode gajian.', 16, 1);
    RETURN;
END

EXEC SIS_PayrollPeriod_Manage @Action = 'GENERATE_YEAR', @Year = 2026, @UserId = @AdminUserId;
EXEC SIS_PayrollPeriod_Manage @Action = 'GENERATE_YEAR', @Year = 2027, @UserId = @AdminUserId;
GO

-- Verifikasi bersambung: period_start tiap periode harus = period_end periode sebelumnya.
-- Tidak ada baris keluar = tidak ada celah / tumpang tindih.
SELECT pp.period_code, prev.period_code AS PrevCode, prev.period_end AS PrevEnd, pp.period_start
FROM payroll_periods pp
OUTER APPLY (
    SELECT TOP 1 p2.period_code, p2.period_end
    FROM payroll_periods p2
    WHERE p2.deleted_at IS NULL AND p2.period_end <= pp.period_start
    ORDER BY p2.period_end DESC
) prev
WHERE pp.deleted_at IS NULL
  AND prev.period_end IS NOT NULL
  AND prev.period_end <> pp.period_start;
GO

SELECT period_year, COUNT(*) AS JumlahPeriode, MIN(period_start) AS Mulai, MAX(period_end) AS Selesai
FROM payroll_periods
WHERE deleted_at IS NULL
GROUP BY period_year
ORDER BY period_year;
GO
