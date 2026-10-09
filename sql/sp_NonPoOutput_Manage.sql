-- Prompt 59: output NON-PO -- pekerjaan di luar PO/bundle yang diinput PIC dari perangkat
-- stasiun (sampel, order toko tanpa PO, dsb). MASUK UPAH resource.
--
-- Pintu masuk MANDIRI, terpisah dari SIS_WorkflowLog_Manage: baris di sini TIDAK menyentuh
-- article_workflow_logs, tidak punya bundle/step/artikel, dan TIDAK ikut mekanisme lock
-- Prompt 55 -- edit/hapus bebas, tanpa approval. Satu-satunya rem adalah periode gajian yang
-- sudah finalized_at (keputusan prompt: "Edit/hapus bebas tanpa lock").
--
-- Periode gajian DIHITUNG ULANG dari @OutputAt setiap CREATE dan UPDATE memakai
-- dbo.SIS_fn_PayrollPeriodIdAt -- fungsi yang SAMA dengan jalur lock, jadi aturan cut-off
-- Sabtu 10:00 cuma punya satu definisi (lihat sql/sp_PayrollPeriod_Manage.sql). Konsekuensi
-- yang disengaja: mengubah tanggal sebuah catatan bisa memindahkannya ke periode lain, dan
-- kedua periode (lama & baru) harus sama-sama belum final.
--
-- Divisi TIDAK pernah datang dari client -- selalu diambil dari resources.division_id.
-- Pengambilan data ada di procedure terpisah: sp_NonPoOutput_List.sql.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_NonPoOutput_Manage
    -- CREATE / UPDATE / DELETE
    @Action         VARCHAR(20),
    @NonPoOutputId  INT = NULL,
    @ResourceId     INT = NULL,          -- resource sesi stasiun; pemilik baris
    @OutputAt       DATETIME2 = NULL,    -- tanggal + jam pekerjaan (penentu periode)
    @Qty            INT = NULL,
    @UnitPrice      DECIMAL(19,4) = NULL,
    @Remark         NVARCHAR(500) = NULL,
    @UserId         INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserId IS NULL
    BEGIN
        RAISERROR('User pencatat tidak dikenal.', 16, 1);
        RETURN;
    END

    DECLARE @DivisionId INT;
    SELECT @DivisionId = division_id
    FROM resources
    WHERE resource_id = @ResourceId AND deleted_at IS NULL;

    IF @DivisionId IS NULL
    BEGIN
        RAISERROR('Operator wajib dipilih.', 16, 1);
        RETURN;
    END

    -- ----- Validasi isi, dipakai CREATE & UPDATE -----
    IF @Action IN ('CREATE', 'UPDATE')
    BEGIN
        SET @Remark = NULLIF(LTRIM(RTRIM(ISNULL(@Remark, N''))), N'');

        IF @OutputAt IS NULL
        BEGIN
            RAISERROR('Tanggal dan jam wajib diisi.', 16, 1);
            RETURN;
        END

        IF @OutputAt > SYSDATETIME()
        BEGIN
            RAISERROR('Tanggal output tidak boleh di masa depan.', 16, 1);
            RETURN;
        END

        IF ISNULL(@Qty, 0) <= 0
        BEGIN
            RAISERROR('Qty wajib diisi dan harus lebih dari 0.', 16, 1);
            RETURN;
        END

        IF ISNULL(@UnitPrice, -1) < 0
        BEGIN
            RAISERROR('Harga per pcs wajib diisi dan tidak boleh negatif.', 16, 1);
            RETURN;
        END

        IF @Remark IS NULL
        BEGIN
            RAISERROR('Keterangan wajib diisi.', 16, 1);
            RETURN;
        END
    END

    -- ----- Periode TUJUAN (dari @OutputAt) -----
    DECLARE @TargetPeriodId INT, @TargetPeriodCode VARCHAR(10), @TargetFinalizedAt DATETIME2;

    IF @Action IN ('CREATE', 'UPDATE')
    BEGIN
        SET @TargetPeriodId = dbo.SIS_fn_PayrollPeriodIdAt(@OutputAt);

        IF @TargetPeriodId IS NULL
        BEGIN
            RAISERROR('Periode gajian untuk tanggal itu belum di-generate. Hubungi admin.', 16, 1);
            RETURN;
        END

        SELECT @TargetPeriodCode = period_code, @TargetFinalizedAt = finalized_at
        FROM payroll_periods WHERE payroll_period_id = @TargetPeriodId;

        IF @TargetFinalizedAt IS NOT NULL
        BEGIN
            RAISERROR('Periode gajian %s sudah final, output tidak bisa dicatat ke sana.', 16, 1, @TargetPeriodCode);
            RETURN;
        END
    END

    -- ----- Periode LAMA (baris yang sedang diubah/dihapus) -----
    -- Dicek terpisah dari periode tujuan: memindahkan catatan KELUAR dari periode yang sudah
    -- final sama saja mengubah angka periode final itu.
    DECLARE @OldPeriodId INT, @OldPeriodCode VARCHAR(10), @OldFinalizedAt DATETIME2;

    IF @Action IN ('UPDATE', 'DELETE')
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM non_po_outputs
            WHERE non_po_output_id = @NonPoOutputId AND deleted_at IS NULL AND resource_id = @ResourceId
        )
        BEGIN
            RAISERROR('Catatan non-PO tidak ditemukan atau bukan milik line ini.', 16, 1);
            RETURN;
        END

        SELECT @OldPeriodId = npo.payroll_period_id, @OldPeriodCode = pp.period_code, @OldFinalizedAt = pp.finalized_at
        FROM non_po_outputs npo
        INNER JOIN payroll_periods pp ON pp.payroll_period_id = npo.payroll_period_id
        WHERE npo.non_po_output_id = @NonPoOutputId;

        IF @OldFinalizedAt IS NOT NULL
        BEGIN
            RAISERROR('Catatan ini ada di periode gajian %s yang sudah final.', 16, 1, @OldPeriodCode);
            RETURN;
        END
    END

    IF @Action = 'CREATE'
    BEGIN
        INSERT INTO non_po_outputs (resource_id, division_id, payroll_period_id, output_at,
                                    qty, unit_price, remark, created_at, created_by)
        VALUES (@ResourceId, @DivisionId, @TargetPeriodId, @OutputAt,
                @Qty, @UnitPrice, @Remark, SYSDATETIME(), @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        -- division_id ikut disegarkan: resource bisa saja dipindah divisi sejak catatan dibuat,
        -- dan kolom itu hanyalah salinan dari resources (bukan input user).
        UPDATE non_po_outputs
        SET division_id = @DivisionId,
            payroll_period_id = @TargetPeriodId,
            output_at = @OutputAt,
            qty = @Qty,
            unit_price = @UnitPrice,
            remark = @Remark,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE non_po_output_id = @NonPoOutputId AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE non_po_outputs
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE non_po_output_id = @NonPoOutputId AND deleted_at IS NULL;
    END

    ELSE
    BEGIN
        RAISERROR('Action tidak dikenal.', 16, 1);
        RETURN;
    END
END;
GO
