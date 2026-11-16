/* =============================================================
   tni.SIS_Satuan_Manage (2026-11-09, alter_78)

   @Action = 'PRIORITAS': pasang (@Prioritas = 1) / lepas (@Prioritas = 0)
   bintang prioritas satuan di Perintah Kerja. Pasang ulang satuan yang sudah
   berbintang tidak mengubah prioritas_at (urutan bintang tetap).

   @Action = 'KUNCI_STOK' (2026-11-11, alter_81): pasang (@Kunci = 1) / lepas
   (@Kunci = 0) kunci stok satuan. Pasang ulang tidak mengubah kunci_stok_at
   (antrean jatah stok antarsatuan tetap). Pembagian stok di tni.v_stok_kunci.

   Butuh alter_78_satuan_prioritas.sql + alter_81_satuan_kunci_stok.sql.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE tni.SIS_Satuan_Manage
    @Action       VARCHAR(20),
    @Id           INT,
    @Prioritas    BIT = NULL,
    @Kunci        BIT = NULL,
    @UserId       INT = NULL,
    @PerangkatId  INT = NULL      -- perangkat pelaksana, bukan user
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @UserId IS NULL
    BEGIN
        RAISERROR(N'User pencatat wajib diisi.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM tni.satuan WHERE satuan_id = @Id AND deleted_at IS NULL)
    BEGIN
        RAISERROR(N'Satuan tidak ditemukan.', 16, 1);
        RETURN;
    END

    IF @Action = 'PRIORITAS'
    BEGIN
        IF @Prioritas IS NULL
        BEGIN
            RAISERROR(N'Nilai prioritas wajib diisi.', 16, 1);
            RETURN;
        END

        IF @Prioritas = 1
            UPDATE tni.satuan
            SET prioritas_at = SYSDATETIME(),
                prioritas_by = @UserId,
                prioritas_perangkat_id = @PerangkatId,
                updated_at = SYSDATETIME(),
                updated_by = @UserId
            WHERE satuan_id = @Id AND deleted_at IS NULL
              AND prioritas_at IS NULL;          -- sudah berbintang: tidak diubah
        ELSE
            UPDATE tni.satuan
            SET prioritas_at = NULL,
                prioritas_by = NULL,
                prioritas_perangkat_id = NULL,
                updated_at = SYSDATETIME(),
                updated_by = @UserId
            WHERE satuan_id = @Id AND deleted_at IS NULL
              AND prioritas_at IS NOT NULL;

        RETURN;
    END

    IF @Action = 'KUNCI_STOK'
    BEGIN
        IF @Kunci IS NULL
        BEGIN
            RAISERROR(N'Nilai kunci stok wajib diisi.', 16, 1);
            RETURN;
        END

        IF @Kunci = 1
            UPDATE tni.satuan
            SET kunci_stok_at = SYSDATETIME(),
                kunci_stok_by = @UserId,
                kunci_stok_perangkat_id = @PerangkatId,
                updated_at = SYSDATETIME(),
                updated_by = @UserId
            WHERE satuan_id = @Id AND deleted_at IS NULL
              AND kunci_stok_at IS NULL;         -- sudah terkunci: antrean tidak berubah
        ELSE
            UPDATE tni.satuan
            SET kunci_stok_at = NULL,
                kunci_stok_by = NULL,
                kunci_stok_perangkat_id = NULL,
                updated_at = SYSDATETIME(),
                updated_by = @UserId
            WHERE satuan_id = @Id AND deleted_at IS NULL
              AND kunci_stok_at IS NOT NULL;

        RETURN;
    END

    RAISERROR(N'Action tidak dikenal.', 16, 1);
END;
GO
