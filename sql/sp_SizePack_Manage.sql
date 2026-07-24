-- Mutasi data size_packs + size_pack_details (CREATE/UPDATE/DELETE), header + detail
-- dalam satu transaksi. Detail dikirim sebagai JSON (@Details, di-parse dengan OPENJSON).
-- UPDATE: baris dengan Id -> update, baris tanpa Id (NULL) -> insert baru,
-- baris lama yang tidak ada lagi di JSON -> soft delete.
-- Pengambilan data ada di procedure terpisah: sp_SizePack_Select.sql.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_SizePack_Manage
    @Action       VARCHAR(20),
    @Id           INT = NULL,
    @BuyerId      INT = NULL,
    @SizePackName VARCHAR(150) = NULL,
    @Details      NVARCHAR(MAX) = NULL,  -- JSON array: [{"Id":null,"SizeName":"S","SortOrder":1,"Description":null}, ...]
    @UserId       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            INSERT INTO size_packs (buyer_id, size_pack_name, created_at, created_by)
            VALUES (@BuyerId, @SizePackName, SYSDATETIME(), @UserId);

            DECLARE @NewSizePackId INT = CAST(SCOPE_IDENTITY() AS INT);

            INSERT INTO size_pack_details (size_pack_id, size_name, sort_order, [description], created_at, created_by)
            SELECT @NewSizePackId, j.SizeName, j.SortOrder, j.[Description], SYSDATETIME(), @UserId
            FROM OPENJSON(@Details)
                WITH (
                    SizeName      VARCHAR(50)  '$.SizeName',
                    SortOrder     INT          '$.SortOrder',
                    [Description] VARCHAR(255) '$.Description'
                ) j;

            COMMIT TRAN;
            SELECT @NewSizePackId AS NewId;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            UPDATE size_packs
            SET buyer_id = @BuyerId,
                size_pack_name = @SizePackName,
                updated_at = SYSDATETIME(),
                updated_by = @UserId
            WHERE size_pack_id = @Id AND deleted_at IS NULL;

            -- Baris dengan Id -> update
            UPDATE spd
            SET spd.size_name = j.SizeName,
                spd.sort_order = j.SortOrder,
                spd.[description] = j.[Description],
                spd.updated_at = SYSDATETIME(),
                spd.updated_by = @UserId
            FROM size_pack_details spd
            INNER JOIN OPENJSON(@Details)
                WITH (
                    Id            INT          '$.Id',
                    SizeName      VARCHAR(50)  '$.SizeName',
                    SortOrder     INT          '$.SortOrder',
                    [Description] VARCHAR(255) '$.Description'
                ) j ON j.Id = spd.size_pack_detail_id
            WHERE spd.size_pack_id = @Id AND spd.deleted_at IS NULL;

            -- Baris lama yang sudah tidak ada di JSON -> soft delete
            -- (harus dijalankan SEBELUM insert baris baru: baris baru belum
            -- punya Id di JSON, jadi kalau insert duluan baris itu akan
            -- langsung ikut ke-soft-delete di sini karena Id barunya juga
            -- tidak ada di JSON)
            UPDATE spd
            SET spd.deleted_at = SYSDATETIME(),
                spd.deleted_by = @UserId
            FROM size_pack_details spd
            WHERE spd.size_pack_id = @Id AND spd.deleted_at IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM OPENJSON(@Details) WITH (Id INT '$.Id') j
                  WHERE j.Id = spd.size_pack_detail_id
              );

            -- Baris tanpa Id -> insert baru
            INSERT INTO size_pack_details (size_pack_id, size_name, sort_order, [description], created_at, created_by)
            SELECT @Id, j.SizeName, j.SortOrder, j.[Description], SYSDATETIME(), @UserId
            FROM OPENJSON(@Details)
                WITH (
                    Id            INT          '$.Id',
                    SizeName      VARCHAR(50)  '$.SizeName',
                    SortOrder     INT          '$.SortOrder',
                    [Description] VARCHAR(255) '$.Description'
                ) j
            WHERE j.Id IS NULL;

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            UPDATE size_packs
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE size_pack_id = @Id AND deleted_at IS NULL;

            UPDATE size_pack_details
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE size_pack_id = @Id AND deleted_at IS NULL;

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END
END;
GO
