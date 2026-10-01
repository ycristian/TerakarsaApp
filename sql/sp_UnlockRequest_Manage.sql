-- Prompt 55: SP request unlock -- SATU-SATUNYA jalan melepas lock baris article_workflow_logs
-- (lihat sql/sp_WorkflowLock_Manage.sql; tidak ada action UNLOCK langsung di sana).
--
-- CREATE/CANCEL dipakai stasiun (UI Prompt 56), APPROVE/REJECT dipakai halaman admin
-- (Prompt 57). Keadaan request diturunkan dari timestamp, tidak ada kolom status:
--   menunggu = approved_at IS NULL AND rejected_at IS NULL AND deleted_at IS NULL
--   dibatalkan pengaju = deleted_at terisi (soft delete)
--
-- APPROVE tidak menghapus header workflow_locks lama -- hanya menandai workflow_lock_items
-- released_at/released_by_request_id dan mengosongkan article_workflow_logs.lock_id. Riwayat
-- "baris ini pernah di-lock ke periode mana, lalu dibuka oleh request mana" tetap utuh, dan
-- LOCK berikutnya membuat item BARU (filtered unique index UX_wli_log_active hanya melarang
-- dua lock AKTIF pada baris yang sama).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_UnlockRequest_Manage
    @Action         VARCHAR(20),
    @Id             INT = NULL,
    @WorkflowLogIds VARCHAR(MAX) = NULL,   -- CSV, pola STRING_SPLIT seperti SP lain
    @Reason         VARCHAR(500) = NULL,
    @DivisionId     INT = NULL,
    @StationId      INT = NULL,
    @ResourceId     INT = NULL,
    @AdminNote      VARCHAR(500) = NULL,
    @UserId         INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserId IS NULL
    BEGIN
        RAISERROR('User pencatat tidak dikenal.', 16, 1);
        RETURN;
    END

    IF @Action = 'CREATE'
    BEGIN
        IF @Reason IS NULL OR LEN(LTRIM(RTRIM(@Reason))) < 5
        BEGIN
            RAISERROR('Alasan wajib diisi, minimal 5 karakter.', 16, 1);
            RETURN;
        END

        IF @DivisionId IS NULL
        BEGIN
            RAISERROR('Divisi tidak dikenal.', 16, 1);
            RETURN;
        END

        IF @ResourceId IS NULL OR NOT EXISTS (
            SELECT 1 FROM resources
            WHERE resource_id = @ResourceId AND division_id = @DivisionId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Operator wajib dipilih.', 16, 1);
            RETURN;
        END

        DECLARE @Ids TABLE (workflow_log_id INT PRIMARY KEY);
        INSERT INTO @Ids (workflow_log_id)
        SELECT DISTINCT CAST(LTRIM(RTRIM(value)) AS INT)
        FROM STRING_SPLIT(ISNULL(@WorkflowLogIds, ''), ',')
        WHERE LTRIM(RTRIM(value)) <> '';

        IF NOT EXISTS (SELECT 1 FROM @Ids)
        BEGIN
            RAISERROR('Pilih minimal satu baris untuk diajukan.', 16, 1);
            RETURN;
        END

        DECLARE @BadIds VARCHAR(500);

        SELECT @BadIds = STUFF((
            SELECT ', ' + CAST(i.workflow_log_id AS VARCHAR(20))
            FROM @Ids i
            WHERE NOT EXISTS (
                SELECT 1 FROM article_workflow_logs awl
                WHERE awl.workflow_log_id = i.workflow_log_id AND awl.deleted_at IS NULL
                  AND awl.division_id = @DivisionId AND awl.lock_id IS NOT NULL
            )
            ORDER BY i.workflow_log_id
            FOR XML PATH(''), TYPE).value('.', 'VARCHAR(500)'), 1, 2, '');

        IF @BadIds IS NOT NULL
        BEGIN
            RAISERROR('Sebagian baris tidak ditemukan, bukan milik divisi ini, atau belum di-lock (ID: %s).', 16, 1, @BadIds);
            RETURN;
        END

        -- Satu baris tidak boleh nyangkut di dua request yang sama-sama menunggu.
        SELECT @BadIds = STUFF((
            SELECT ', ' + CAST(i.workflow_log_id AS VARCHAR(20))
            FROM @Ids i
            WHERE EXISTS (
                SELECT 1
                FROM unlock_request_items uri
                INNER JOIN unlock_requests ur ON ur.request_id = uri.request_id
                WHERE uri.workflow_log_id = i.workflow_log_id
                  AND ur.approved_at IS NULL AND ur.rejected_at IS NULL AND ur.deleted_at IS NULL
            )
            ORDER BY i.workflow_log_id
            FOR XML PATH(''), TYPE).value('.', 'VARCHAR(500)'), 1, 2, '');

        IF @BadIds IS NOT NULL
        BEGIN
            RAISERROR('Sebagian baris sudah diajukan dan menunggu approval (ID: %s).', 16, 1, @BadIds);
            RETURN;
        END

        IF EXISTS (
            SELECT 1
            FROM @Ids i
            INNER JOIN article_workflow_logs awl ON awl.workflow_log_id = i.workflow_log_id
            INNER JOIN workflow_locks wl ON wl.lock_id = awl.lock_id
            INNER JOIN payroll_periods pp ON pp.payroll_period_id = wl.payroll_period_id
            WHERE pp.finalized_at IS NOT NULL
        )
        BEGIN
            RAISERROR('Sebagian baris berada di periode gajian yang sudah final.', 16, 1);
            RETURN;
        END

        IF @StationId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM stations WHERE station_id = @StationId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Stasiun tidak ditemukan.', 16, 1);
            RETURN;
        END

        DECLARE @NewRequestId INT, @ItemCount INT;

        BEGIN TRAN;
        BEGIN TRY
            INSERT INTO unlock_requests (
                division_id, station_id, reason, requested_by_resource_id, created_at, created_by
            )
            VALUES (
                @DivisionId, @StationId, LTRIM(RTRIM(@Reason)), @ResourceId, SYSDATETIME(), @UserId
            );

            SET @NewRequestId = CAST(SCOPE_IDENTITY() AS INT);

            -- lock_item_id = item AKTIF baris itu (released_at IS NULL) pada lock yang sedang
            -- menunjuknya -- inilah yang dilepas kalau request ini disetujui.
            INSERT INTO unlock_request_items (request_id, workflow_log_id, lock_item_id, created_at, created_by)
            SELECT @NewRequestId, awl.workflow_log_id, wli.lock_item_id, SYSDATETIME(), @UserId
            FROM @Ids i
            INNER JOIN article_workflow_logs awl ON awl.workflow_log_id = i.workflow_log_id
            INNER JOIN workflow_lock_items wli ON wli.workflow_log_id = awl.workflow_log_id
                AND wli.lock_id = awl.lock_id AND wli.released_at IS NULL AND wli.deleted_at IS NULL;

            SET @ItemCount = @@ROWCOUNT;

            IF @ItemCount <> (SELECT COUNT(*) FROM @Ids)
            BEGIN
                RAISERROR('Sebagian baris tidak punya lock aktif yang cocok, muat ulang data.', 16, 1);
                ROLLBACK TRAN;
                RETURN;
            END

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH

        SELECT @NewRequestId AS NewId, @ItemCount AS ItemCount;
    END

    ELSE IF @Action = 'CANCEL'
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM unlock_requests
            WHERE request_id = @Id AND division_id = @DivisionId
              AND approved_at IS NULL AND rejected_at IS NULL AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Pengajuan tidak ditemukan atau sudah diproses.', 16, 1);
            RETURN;
        END

        UPDATE unlock_requests
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE request_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'APPROVE'
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM unlock_requests
            WHERE request_id = @Id AND approved_at IS NULL AND rejected_at IS NULL AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Pengajuan tidak ditemukan atau sudah diproses.', 16, 1);
            RETURN;
        END

        -- Dicek ULANG di sini (bukan cuma saat CREATE) -- periode bisa difinalisasi setelah
        -- pengajuan masuk.
        IF EXISTS (
            SELECT 1
            FROM unlock_request_items uri
            INNER JOIN workflow_lock_items wli ON wli.lock_item_id = uri.lock_item_id
            INNER JOIN workflow_locks wl ON wl.lock_id = wli.lock_id
            INNER JOIN payroll_periods pp ON pp.payroll_period_id = wl.payroll_period_id
            WHERE uri.request_id = @Id AND pp.finalized_at IS NOT NULL
        )
        BEGIN
            RAISERROR('Periode gajian salah satu baris sudah final, pengajuan tidak bisa disetujui.', 16, 1);
            RETURN;
        END

        -- Lock item harus masih aktif DAN baris log masih menunjuk lock item itu -- kalau
        -- sudah bergeser (dilepas request lain, di-lock ulang), pengajuan ini sudah basi.
        IF EXISTS (
            SELECT 1
            FROM unlock_request_items uri
            INNER JOIN workflow_lock_items wli ON wli.lock_item_id = uri.lock_item_id
            INNER JOIN article_workflow_logs awl ON awl.workflow_log_id = uri.workflow_log_id
            WHERE uri.request_id = @Id
              AND (wli.released_at IS NOT NULL OR wli.deleted_at IS NOT NULL
                   OR awl.lock_id IS NULL OR awl.lock_id <> wli.lock_id)
        )
        BEGIN
            RAISERROR('Lock sebagian baris sudah berubah sejak diajukan. Tolak pengajuan ini dan minta diajukan ulang.', 16, 1);
            RETURN;
        END

        BEGIN TRAN;
        BEGIN TRY
            UPDATE unlock_requests
            SET approved_at = SYSDATETIME(),
                approved_by = @UserId,
                admin_note = NULLIF(LTRIM(RTRIM(@AdminNote)), ''),
                updated_at = SYSDATETIME(),
                updated_by = @UserId
            WHERE request_id = @Id;

            UPDATE wli
            SET wli.released_at = SYSDATETIME(),
                wli.released_by_request_id = @Id,
                wli.updated_at = SYSDATETIME(),
                wli.updated_by = @UserId
            FROM workflow_lock_items wli
            INNER JOIN unlock_request_items uri ON uri.lock_item_id = wli.lock_item_id
            WHERE uri.request_id = @Id;

            UPDATE awl
            SET awl.lock_id = NULL
            FROM article_workflow_logs awl
            INNER JOIN unlock_request_items uri ON uri.workflow_log_id = awl.workflow_log_id
            WHERE uri.request_id = @Id;

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END

    ELSE IF @Action = 'REJECT'
    BEGIN
        IF @AdminNote IS NULL OR LTRIM(RTRIM(@AdminNote)) = ''
        BEGIN
            RAISERROR('Catatan admin wajib diisi saat menolak.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (
            SELECT 1 FROM unlock_requests
            WHERE request_id = @Id AND approved_at IS NULL AND rejected_at IS NULL AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Pengajuan tidak ditemukan atau sudah diproses.', 16, 1);
            RETURN;
        END

        UPDATE unlock_requests
        SET rejected_at = SYSDATETIME(),
            rejected_by = @UserId,
            admin_note = LTRIM(RTRIM(@AdminNote)),
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE request_id = @Id;
    END

    ELSE
    BEGIN
        RAISERROR('Action tidak valid.', 16, 1);
        RETURN;
    END
END;
GO
