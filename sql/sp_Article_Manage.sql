-- Mutasi data articles + article_sizes (CREATE/UPDATE/DELETE), header + ukuran
-- dalam satu transaksi. Ukuran dikirim sebagai JSON (@Sizes, di-parse dengan OPENJSON),
-- satu entri per size_pack_detail_id (grid ukuran di UI selalu menampilkan seluruh size
-- pack yang dipilih -- ini hanya soal tampilan, lihat aturan simpan Prompt 19 di bawah).
--
-- Prompt 19 -- article_sizes hanya dibuat/tetap hidup untuk entri ber-qty order > 0:
--   CREATE: hanya entri JSON dengan Qty > 0 yang di-insert.
--   UPDATE:
--     1. Entri Qty > 0, sudah ada baris hidup -> update qty/bundle_qty (seperti sebelumnya).
--     2. Entri Qty > 0, belum ada baris hidup -> insert baru (tidak ada unique constraint
--        filtered yang menghalangi, jadi baris soft-delete lama untuk size_pack_detail_id
--        yang sama TIDAK di-restore -- selalu insert baris baru untuk kesederhanaan).
--     3. Entri Qty = 0 (atau size template tidak dikirim), tapi ada baris hidup:
--        - Belum direferensikan bundles/article_workflow_logs hidup -> soft delete.
--        - Sudah direferensikan -> RAISERROR, batalkan SELURUH simpan (termasuk header).
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

            -- Prompt 19: hanya size ber-qty order > 0 yang dibuat baris article_sizes-nya.
            INSERT INTO article_sizes (article_id, size_pack_detail_id, qty, bundle_qty, created_at, created_by)
            SELECT @NewArticleId, j.SizePackDetailId, j.Qty, j.BundleQty, SYSDATETIME(), @UserId
            FROM OPENJSON(@Sizes)
                WITH (
                    SizePackDetailId INT '$.SizePackDetailId',
                    Qty              INT '$.Qty',
                    BundleQty        INT '$.BundleQty'
                ) j
            WHERE j.Qty > 0;

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
            -- Prompt 19: entri yang mau dikosongkan (Qty = 0/tidak dikirim) tapi baris
            -- hidupnya sudah dipakai bundle/log produksi -> tolak SELURUH simpan.
            DECLARE @BlockedSizeName VARCHAR(50);
            SELECT TOP 1 @BlockedSizeName = spd.size_name
            FROM article_sizes asz
            INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
            WHERE asz.article_id = @Id AND asz.deleted_at IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM OPENJSON(@Sizes) WITH (SizePackDetailId INT '$.SizePackDetailId', Qty INT '$.Qty') j
                  WHERE j.SizePackDetailId = asz.size_pack_detail_id AND j.Qty > 0
              )
              AND (
                  EXISTS (SELECT 1 FROM bundles b WHERE b.article_size_id = asz.article_size_id AND b.deleted_at IS NULL)
                  OR EXISTS (SELECT 1 FROM article_workflow_logs awl WHERE awl.article_size_id = asz.article_size_id AND awl.deleted_at IS NULL)
              );

            IF @BlockedSizeName IS NOT NULL
            BEGIN
                RAISERROR('Size %s sudah memiliki bundle/log produksi, qty tidak boleh dikosongkan.', 16, 1, @BlockedSizeName);
            END

            UPDATE articles
            SET size_pack_id = @SizePackId,
                article_name = @ArticleName,
                style = @Style,
                color = @Color,
                updated_at = SYSDATETIME(),
                updated_by = @UserId
            WHERE article_id = @Id AND deleted_at IS NULL;

            -- 1. Entri Qty > 0, baris hidup sudah ada -> update qty/bundle_qty
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
            WHERE asz.article_id = @Id AND asz.deleted_at IS NULL AND j.Qty > 0;

            -- 2. Entri Qty > 0, belum ada baris hidup (artikel baru/ganti size pack/size
            --    yang tadinya kosong sekarang diisi) -> insert baru. Tidak ada unique
            --    constraint filtered pada article_sizes, jadi baris soft-delete lama untuk
            --    size_pack_detail_id yang sama (bila ada) TIDAK di-restore.
            INSERT INTO article_sizes (article_id, size_pack_detail_id, qty, bundle_qty, created_at, created_by)
            SELECT @Id, j.SizePackDetailId, j.Qty, j.BundleQty, SYSDATETIME(), @UserId
            FROM OPENJSON(@Sizes)
                WITH (
                    SizePackDetailId INT '$.SizePackDetailId',
                    Qty              INT '$.Qty',
                    BundleQty        INT '$.BundleQty'
                ) j
            WHERE j.Qty > 0
              AND NOT EXISTS (
                  SELECT 1 FROM article_sizes asz
                  WHERE asz.article_id = @Id AND asz.size_pack_detail_id = j.SizePackDetailId AND asz.deleted_at IS NULL
              );

            -- 3. Entri Qty = 0/tidak dikirim, baris hidup ada dan TIDAK direferensikan
            --    (sudah lolos guard di atas) -> soft delete.
            UPDATE asz
            SET asz.deleted_at = SYSDATETIME(),
                asz.deleted_by = @UserId
            FROM article_sizes asz
            WHERE asz.article_id = @Id AND asz.deleted_at IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM OPENJSON(@Sizes) WITH (SizePackDetailId INT '$.SizePackDetailId', Qty INT '$.Qty') j
                  WHERE j.SizePackDetailId = asz.size_pack_detail_id AND j.Qty > 0
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
