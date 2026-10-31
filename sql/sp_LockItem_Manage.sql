-- Prompt 83: koreksi harga satu lock item oleh admin produksi, dari halaman Rekap Gajian.
--
-- Harga melekat ke LOCK ITEM -- bukan ke article_workflow_logs dan bukan ke manual_outputs.
-- Mengubah harga di sini TIDAK mengubah master tarif article_workflows.unit_price, dan
-- sebaliknya: mengubah master tarif tidak mengubah harga yang sudah dibekukan.
--
-- NILAI MINUS DIPERBOLEHKAN (Bagian 3.4) -- itu yang dipakai untuk baris potongan, dan
-- juga memungkinkan koreksi negatif pada baris LOG. Karena itu TIDAK ADA validasi >= 0
-- di sini; jangan menambahkannya.
--
-- Satu-satunya rem: periode gajian baris itu belum finalized_at.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_LockItem_UpdatePrice
    @LockItemId INT,
    @UnitPrice  DECIMAL(19,4) = NULL,   -- NULL = kosongkan lagi (kembali jadi "belum diisi")
    @UserId     INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserId IS NULL
    BEGIN
        RAISERROR('User pencatat tidak dikenal.', 16, 1);
        RETURN;
    END

    DECLARE @PeriodCode VARCHAR(10), @FinalizedAt DATETIME2, @Ada BIT = 0;

    SELECT @Ada = 1, @PeriodCode = pp.period_code, @FinalizedAt = pp.finalized_at
    FROM workflow_lock_items wli
    INNER JOIN workflow_locks wl ON wl.lock_id = wli.lock_id AND wl.deleted_at IS NULL
    INNER JOIN payroll_periods pp ON pp.payroll_period_id = wl.payroll_period_id
    WHERE wli.lock_item_id = @LockItemId
      AND wli.released_at IS NULL AND wli.deleted_at IS NULL;

    -- Lock item yang sudah DILEPAS (released_at) sengaja ikut ditolak di sini: baris itu
    -- tidak lagi jadi isi periode mana pun, jadi harganya tidak ada artinya.
    IF @Ada = 0
    BEGIN
        RAISERROR('Baris rekap tidak ditemukan atau lock-nya sudah dilepas. Muat ulang data.', 16, 1);
        RETURN;
    END

    IF @FinalizedAt IS NOT NULL
    BEGIN
        RAISERROR('Periode gajian %s sudah final, harga tidak bisa diubah.', 16, 1, @PeriodCode);
        RETURN;
    END

    UPDATE workflow_lock_items
    SET unit_price = @UnitPrice,
        updated_at = SYSDATETIME(),
        updated_by = @UserId
    WHERE lock_item_id = @LockItemId;
END;
GO
