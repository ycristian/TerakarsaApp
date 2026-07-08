-- Mutasi data articles + article_sizes (CREATE/UPDATE/DELETE), header + ukuran
-- dalam satu transaksi. Ukuran dikirim sebagai JSON (@Sizes, di-parse dengan OPENJSON),
-- satu baris per size_pack_detail_id (grid ukuran selalu mengikuti size pack yang dipilih,
-- tidak bisa tambah/hapus baris manual seperti size_pack_details).
-- UPDATE: baris dengan size_pack_detail_id yang sudah ada -> update qty/bundle_qty,
-- baris dengan size_pack_detail_id baru (mis. setelah ganti size pack) -> insert,
-- baris lama yang size_pack_detail_id-nya tidak ada lagi di JSON -> soft delete.
-- DELETE = soft delete artikel + article_sizes + article_photos-nya.
-- Pengambilan data ada di procedure terpisah: sp_Article_Select.sql.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Article_Manage
    @Action      VARCHAR(20),
    @Id          INT = NULL,
    @ProjectId   INT = NULL,
    @SizePackId  INT = NULL,
    @ArticleName VARCHAR(150) = NULL,
    @Style       VARCHAR(100) = NULL,
    @Color       VARCHAR(100) = NULL,
    @Sizes       NVARCHAR(MAX) = NULL,  -- JSON array: [{"SizePackDetailId":1,"Qty":0,"BundleQty":0}, ...]
    @UserId      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            INSERT INTO articles (project_id, size_pack_id, article_name, style, color, created_at, created_by)
            VALUES (@ProjectId, @SizePackId, @ArticleName, @Style, @Color, SYSDATETIME(), @UserId);

            DECLARE @NewArticleId INT = CAST(SCOPE_IDENTITY() AS INT);

            INSERT INTO article_sizes (article_id, size_pack_detail_id, qty, bundle_qty, created_at, created_by)
            SELECT @NewArticleId, j.SizePackDetailId, j.Qty, j.BundleQty, SYSDATETIME(), @UserId
            FROM OPENJSON(@Sizes)
                WITH (
                    SizePackDetailId INT '$.SizePackDetailId',
                    Qty              INT '$.Qty',
                    BundleQty        INT '$.BundleQty'
                ) j;

            COMMIT TRAN;
            SELECT @NewArticleId AS NewId;
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
            UPDATE articles
            SET size_pack_id = @SizePackId,
                article_name = @ArticleName,
                style = @Style,
                color = @Color,
                updated_at = SYSDATETIME(),
                updated_by = @UserId
            WHERE article_id = @Id AND deleted_at IS NULL;

            -- Baris yang size_pack_detail_id-nya sudah ada -> update qty/bundle_qty
            UPDATE asz
            SET asz.qty = j.Qty,
                asz.bundle_qty = j.BundleQty,
                asz.updated_at = SYSDATETIME(),
                asz.updated_by = @UserId
            FROM article_sizes asz
            INNER JOIN OPENJSON(@Sizes)
                WITH (
                    SizePackDetailId INT '$.SizePackDetailId',
                    Qty              INT '$.Qty',
                    BundleQty        INT '$.BundleQty'
                ) j ON j.SizePackDetailId = asz.size_pack_detail_id
            WHERE asz.article_id = @Id AND asz.deleted_at IS NULL;

            -- Baris dengan size_pack_detail_id baru (mis. setelah ganti size pack) -> insert
            INSERT INTO article_sizes (article_id, size_pack_detail_id, qty, bundle_qty, created_at, created_by)
            SELECT @Id, j.SizePackDetailId, j.Qty, j.BundleQty, SYSDATETIME(), @UserId
            FROM OPENJSON(@Sizes)
                WITH (
                    SizePackDetailId INT '$.SizePackDetailId',
                    Qty              INT '$.Qty',
                    BundleQty        INT '$.BundleQty'
                ) j
            WHERE NOT EXISTS (
                SELECT 1 FROM article_sizes asz
                WHERE asz.article_id = @Id AND asz.size_pack_detail_id = j.SizePackDetailId AND asz.deleted_at IS NULL
            );

            -- Baris lama yang size_pack_detail_id-nya sudah tidak ada di JSON -> soft delete
            UPDATE asz
            SET asz.deleted_at = SYSDATETIME(),
                asz.deleted_by = @UserId
            FROM article_sizes asz
            WHERE asz.article_id = @Id AND asz.deleted_at IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM OPENJSON(@Sizes) WITH (SizePackDetailId INT '$.SizePackDetailId') j
                  WHERE j.SizePackDetailId = asz.size_pack_detail_id
              );

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
            UPDATE articles
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE article_id = @Id AND deleted_at IS NULL;

            UPDATE article_sizes
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE article_id = @Id AND deleted_at IS NULL;

            UPDATE article_photos
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE article_id = @Id AND deleted_at IS NULL;

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END
END;
GO
