-- alter_79 (2026-11-09): kapasitas box TIDAK lagi membatasi isi; default 50 -> 52.
--
-- 1. Default constraint tni.box.kapasitas diganti ke 52 (constraint lama tanpa nama,
--    dicari lewat sys.default_constraints). Idempotent: dilewati kalau sudah 52.
-- 2. Penolakan "Box ... penuh" dihapus dari tni.SIS_Box_Scan -- jalankan ulang
--    sql/tni/sp_Box.sql SETELAH script ini.
-- Box lama tetap dengan kapasitasnya (tidak diubah).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @Nama SYSNAME, @Def NVARCHAR(MAX), @Sql NVARCHAR(400);

SELECT @Nama = dc.name, @Def = dc.definition
FROM sys.default_constraints dc
JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE dc.parent_object_id = OBJECT_ID('tni.box') AND c.name = 'kapasitas';

IF @Nama IS NOT NULL AND REPLACE(REPLACE(@Def, '(', ''), ')', '') <> '52'
BEGIN
    SET @Sql = N'ALTER TABLE tni.box DROP CONSTRAINT ' + QUOTENAME(@Nama);
    EXEC sp_executesql @Sql;
    SET @Nama = NULL;
END

IF @Nama IS NULL
    ALTER TABLE tni.box ADD CONSTRAINT DF_tni_box_kapasitas DEFAULT 52 FOR kapasitas;
GO
