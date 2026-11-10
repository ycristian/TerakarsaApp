-- Audit log lokal PDH TNI AD (2026-11-09).
--
-- Dua SP BACA untuk TniAuditSnapshotService (API): setiap N menit semua tabel
-- schema `tni` dibaca utuh, dibandingkan dengan snapshot sebelumnya di disk,
-- dan perubahan yang tidak punya pasangan di jurnal request API ditandai
-- TANPA LOG. Tidak ada tabel baru: hasilnya hanya file di Tni:AuditLog:Folder.
--
-- Tabel dibaca DINAMIS dari sys.tables, jadi tabel tni baru otomatis ikut.
-- Kolom besar (MAX/xml/image/text) dan kolom berisi token dikembalikan sebagai
-- hash SHA-256 ('#' + hex) -- perubahan tetap terdeteksi, isi besar/rahasia
-- tidak ikut tersimpan di file log.
--
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: tabel tni punya filtered index.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Daftar tabel schema tni + kolom primary key (dipisah koma, urut key_ordinal)
-- + jam server DB (untuk mengoreksi selisih jam DB vs API saat mencocokkan
-- jurnal).
CREATE OR ALTER PROCEDURE tni.SIS_AuditLog_Tabel
AS
BEGIN
    SET NOCOUNT ON;

    SELECT t.name AS TableName,
           pk.Kolom AS PkKolom,
           SYSDATETIME() AS DbNow
    FROM sys.tables t
    OUTER APPLY (
        SELECT STRING_AGG(c.name, ',') WITHIN GROUP (ORDER BY ic.key_ordinal) AS Kolom
        FROM sys.indexes i
        JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
        JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE i.object_id = t.object_id AND i.is_primary_key = 1
    ) pk
    WHERE t.schema_id = SCHEMA_ID('tni')
    ORDER BY t.name;
END
GO

-- Isi utuh satu tabel tni (termasuk baris soft delete -- justru itu yang
-- perlu dipantau). @Tabel divalidasi ke sys.tables schema tni sebelum
-- dirangkai jadi dynamic SQL.
CREATE OR ALTER PROCEDURE tni.SIS_AuditLog_Baca
    @Tabel SYSNAME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ObjectId INT = (SELECT t.object_id FROM sys.tables t
                              WHERE t.schema_id = SCHEMA_ID('tni') AND t.name = @Tabel);
    IF @ObjectId IS NULL
    BEGIN
        RAISERROR('Tabel tni.%s tidak ditemukan.', 16, 1, @Tabel);
        RETURN;
    END

    DECLARE @Kolom NVARCHAR(MAX) =
    (
        SELECT STRING_AGG(CAST(
                   CASE
                       WHEN ty.name IN ('xml', 'text', 'ntext', 'image', 'sql_variant')
                         OR c.max_length = -1
                         OR c.name LIKE '%token%'
                       THEN N'CASE WHEN ' + QUOTENAME(c.name) + N' IS NULL THEN NULL ELSE ''#'' + '
                          + N'CONVERT(VARCHAR(64), HASHBYTES(''SHA2_256'', '
                          + CASE WHEN ty.name IN ('image', 'binary', 'varbinary')
                                 THEN N'CAST(' + QUOTENAME(c.name) + N' AS VARBINARY(MAX))'
                                 ELSE N'CAST(CAST(' + QUOTENAME(c.name) + N' AS NVARCHAR(MAX)) AS VARBINARY(MAX))'
                            END
                          + N'), 2) END AS ' + QUOTENAME(c.name)
                       WHEN ty.name IN ('binary', 'varbinary', 'timestamp', 'rowversion')
                       THEN N'CONVERT(VARCHAR(MAX), CAST(' + QUOTENAME(c.name) + N' AS VARBINARY(MAX)), 2) AS '
                          + QUOTENAME(c.name)
                       ELSE QUOTENAME(c.name)
                   END AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY c.column_id)
        FROM sys.columns c
        JOIN sys.types ty ON ty.user_type_id = c.user_type_id
        WHERE c.object_id = @ObjectId
    );

    DECLARE @Sql NVARCHAR(MAX) = N'SELECT ' + @Kolom + N' FROM tni.' + QUOTENAME(@Tabel) + N';';
    EXEC sys.sp_executesql @Sql;
END
GO
